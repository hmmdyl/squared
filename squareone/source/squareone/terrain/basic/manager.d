module squareone.terrain.basic.manager;

import squareone.terrain.basic.chunk;
import squareone.terrain.gen.noisegen;
import squareone.voxel;
import moxane.core;
import moxane.graphics.renderer;
import moxane.utils.maybe;

import dlib.math;
import dlib.geometry : Frustum, Sphere;
import std.math : sqrt;
import std.datetime.stopwatch;
import std.parallelism;
import containers;
import core.thread;
import core.cpuid : threadsPerCPU, coresPerCPU;

final class BasicTerrainRenderer : IRenderable
{
	enum CullMode
	{
		none,
		skip,
		all
	}

	CullMode cullingMode;

	BasicTerrainManager btm;
	invariant { assert(btm !is null); }

	this(BasicTerrainManager btm, CullMode cullingMode = CullMode.all)
	{ this.btm = btm; this.cullingMode = cullingMode; }

	float renderTime = 0f;
	float prepareTime = 0f;

	int drawCallsPhys, drawCallsRefrac;

	private size_t translucentCount;

	void render(Renderer renderer, ref LocalContext lc, out uint drawCalls, out uint numVerts)
	{
		Matrix4f vp = lc.projection * lc.view;
		Frustum frustum = Frustum(vp);

		const Vector3i min = btm.cameraPositionChunk.toVec3i - btm.settings.removeRange;
		const Vector3i max = btm.cameraPositionChunk.toVec3i + (btm.settings.removeRange + 1);

		StopWatch sw = StopWatch(AutoStart.yes);
		StopWatch trueSw = StopWatch(AutoStart.no);
		scope(exit)
		{
			sw.stop;
			renderTime += sw.peek.total!"nsecs" / 1_000_000_000f;
			prepareTime = trueSw.peek.total!"nsecs" / 1_000_000_000f;
		}

		foreach(proc; 0 .. btm.resources.processorCount)
		{
			IProcessor p = btm.resources.getProcessor(proc);
			trueSw.start;
			p.prepareRender(renderer);
			trueSw.stop;
			scope(exit) p.endRender;

			if(cullingMode == CullMode.none)
			{
				foreach(BasicChunk chunk; btm.chunksTerrain)
					p.render(chunk.chunk, lc, drawCalls, numVerts);
			}
			else if(cullingMode == CullMode.skip)
			{
				enum skipSize = 2;
				enum skipSizeHalf = skipSize / 2;

				for(int cx = min.x; cx < max.x; cx += skipSize)
				for(int cy = min.y; cy < max.y; cy += skipSize)
				for(int cz = min.z; cz < max.z; cz += skipSize)
				{
					Vector3i centre = Vector3i(cx + skipSizeHalf, cy + skipSizeHalf, cz + skipSizeHalf);
					Vector3f centreReal = Vector3f(centre.x * ChunkData.chunkDimensionsMetres, centre.y * ChunkData.chunkDimensionsMetres, centre.z * ChunkData.chunkDimensionsMetres);
					enum float radius = sqrt(128f);
					Sphere s = Sphere(centreReal, radius);

					if(!frustum.intersectsSphere(s))
						continue;

					foreach(int cix; cx .. cx + skipSize)
					foreach(int ciy; cy .. cy + skipSize)
					foreach(int ciz; cz .. cz + skipSize)
					{
						BasicChunk* chunk = ChunkPosition(cix, ciy, ciz) in btm.chunksTerrain;
						if(chunk is null)
							continue;

						p.render(chunk.chunk, lc, drawCalls, numVerts);
					}
				}
			}
			else if(cullingMode == CullMode.all)
			{
				bool shouldRender(BasicChunk chunk)
				{
					immutable Vector3f chunkPosReal = chunk.position.toVec3f;
					immutable float dimReal = ChunkData.chunkDimensionsMetres * chunk.chunk.blockskip;
					immutable Vector3f center = Vector3f(chunkPosReal.x + dimReal * 0.5f, chunkPosReal.y + dimReal * 0.5f, chunkPosReal.z + dimReal * 0.5f);
					immutable float radius = sqrt(dimReal ^^ 2 + dimReal ^^ 2);
					Sphere s = Sphere(center, radius);

					return frustum.intersectsSphere(s);
				}

				foreach(BasicChunk chunk; btm.chunksTerrain)
				{
					if(!shouldRender(chunk)) continue;

					uint dc;
					p.render(chunk.chunk, lc, dc, numVerts);
					drawCallsPhys += dc;
					drawCalls += dc;
				}
			}
		}
	}
}

struct BasicTMSettings
{
	Vector3i addRange, extendedAddRange, removeRange;
	Vector3i playerLocalRange;
	Resources resources;
}

enum ChunkState
{
	deallocated,
	/// memory is assigned, but no voxel data.
	notLoaded,
	hibernated,
	active
}

final class BasicTerrainManager
{
	Resources resources;
	Moxane moxane;

	private BasicChunk[ChunkPosition] chunksTerrain;
	private ChunkState[ChunkPosition] chunkStates;

	@property size_t numChunks() const { return chunksTerrain.length; }

	const BasicTMSettings settings;

	Vector3f cameraPosition;
	ChunkPosition cameraPositionChunk, cameraPositionPreviousChunk;
	NoiseGeneratorManager noiseGeneratorManager;

	VoxelInteraction voxelInteraction;
	ChunkInteraction chunkInteraction;

	uint chunksCreated, chunksHibernated, chunksRemoved, chunksCompressed, chunksDecompressed;
	uint noiseCompleted, meshOrders;

	private StopWatch oneSecondSw;
	private uint noiseCompletedCounter;
	uint noiseCompletedSecond;

	this(Moxane moxane, BasicTMSettings settings)
	{
		this.moxane = moxane;
		this.settings = settings;
		resources = settings.resources;

		voxelInteraction = new VoxelInteraction(this);
		chunkInteraction = new ChunkInteraction(this);

		import std.stdio;
		writeln(threadsPerCPU, " ", coresPerCPU);

		noiseGeneratorManager = new NoiseGeneratorManager(resources, coresPerCPU, () => new DefaultNoiseGenerator(moxane), 0);
		auto ecpcNum = (settings.extendedAddRange.x * 2 + 1) * (settings.extendedAddRange.y * 2 + 1) * (settings.extendedAddRange.z * 2 + 1);
		extensionCPCache = new ChunkPosition[ecpcNum];

		oneSecondSw.start;
	}

	~this()
	{
		destroy(noiseGeneratorManager);
	}

	void update()
	{
		manageChunks;
	}

	void manageChunks()
	{
		const ChunkPosition cp = ChunkPosition.fromVec3f(cameraPosition);
		cameraPositionPreviousChunk = cameraPositionChunk;
		cameraPositionChunk = cp;

		//addChunksLocal(cp);
		addChunksExtension(cp);

		voxelInteraction.run;

		//noiseGeneratorManager.pumpCompletedQueue;
		foreach(ref BasicChunk bc; chunksTerrain)
		{
			manageChunkState(bc);
			removeChunkHandler(bc, cp);
		}

		if(oneSecondSw.peek.total!"seconds"() >= 1)
		{
			oneSecondSw.reset;
			noiseCompletedSecond = noiseCompletedCounter;
			noiseCompletedCounter = 0;
		}
	}

	private BasicChunk createChunk(ChunkPosition pos, bool needsData = true)
	{
		Chunk c = new Chunk(resources);
		c.initialise;
		c.needsData = needsData;
		c.lod = 0;
		c.blockskip = 2 ^^ c.lod;
		c.isCompressed = false;
		return BasicChunk(c, pos);
	}

	private void addChunksLocal(const ChunkPosition cp)
	{
		if(cameraPositionChunk == cameraPositionPreviousChunk)
			return;

		Vector3i lower = Vector3i(
			cp.x - settings.addRange.x,
			cp.y - settings.addRange.y,
			cp.z - settings.addRange.z);
		Vector3i upper = Vector3i(
			cp.x + settings.addRange.x,
			cp.y + settings.addRange.y,
			cp.z + settings.addRange.z);

		int numChunksAdded;
		int cs = 1;

		for(int x = lower.x; x < upper.x; x += cs)
		{
			for(int y = lower.y; y < upper.y; y += cs)
			{
				for(int z = lower.z; z < upper.z; z += cs)
				{
					//if(numChunksAdded > 1000) return;

					auto newCp = ChunkPosition(x, y, z);

					ChunkState* getter = newCp in chunkStates;
					bool absent = getter is null || *getter == ChunkState.deallocated;
					bool doAdd = absent || (isInPlayerLocalBounds(cp, newCp) && *getter == ChunkState.hibernated);

					if(doAdd)
					{
						auto chunk = createChunk(newCp);
						chunksTerrain[newCp] = chunk;
						chunkStates[newCp] = ChunkState.notLoaded;
						//chunkDefer.addition(newCp, chunk);

						//numChunksAdded++;
						chunksCreated++;
					}
				}
			}
		}
	}

	private void removeChunkHandler(ref BasicChunk chunk, const ChunkPosition camera)
	{
		if(!isChunkInBounds(camera, chunk.position))
		{
			if(chunk.chunk.needsData || chunk.chunk.dataLoadBlocking || chunk.chunk.dataLoadCompleted ||
			   chunk.chunk.needsMesh || chunk.chunk.isAnyMeshBlocking || chunk.chunk.readonlyRefs > 0)
				chunk.chunk.pendingRemove = true;
			else
			{
				foreach(int proc; 0 .. resources.processorCount)
					resources.getProcessor(proc).removeChunk(chunk.chunk);

				chunksTerrain.remove(chunk.position);
				chunkStates.remove(chunk.position);
				chunk.chunk.deinitialise();

				destroy(chunk.chunk);

				chunksRemoved++;
			}
		}
	}

	private StopWatch addExtensionSortSw;
	private bool isExtensionCacheSorted;
	private ChunkPosition[] extensionCPCache;
	private size_t extensionCPBias, extensionCPLength;

	private void addChunksExtension(const ChunkPosition cam)
	{
		bool doSort;

		if(!addExtensionSortSw.running)
		{
			addExtensionSortSw.start;
			doSort = true;
		}
		if(addExtensionSortSw.peek.total!"msecs"() >= 300 && cameraPositionChunk != cameraPositionPreviousChunk)
		{
			addExtensionSortSw.reset;
			addExtensionSortSw.start;
			doSort = true;
		}

		if(doSort)
		{
			isExtensionCacheSorted = false;

			void sortTask(ChunkPosition[] cache)
			{
				import std.algorithm.sorting : sort;

				ChunkPosition lc = cam;
				immutable camf = lc.toVec3f().lengthsqr;

				auto cdCmp(ChunkPosition x, ChunkPosition y)
				{
					float x1 = x.toVec3f.lengthsqr - camf;
					float y1 = y.toVec3f.lengthsqr - camf;
					return x1 < y1;
				}

				enum int cs = 1;

				Vector3i lower;
				lower.x = lc.x / cs - settings.extendedAddRange.x;
				lower.y = lc.y / cs - settings.extendedAddRange.y;
				lower.z = lc.z / cs - settings.extendedAddRange.z;
				Vector3i upper;
				upper.x = lc.x / cs + settings.extendedAddRange.x;
				upper.y = lc.y / cs + settings.extendedAddRange.y;
				upper.z = lc.z / cs + settings.extendedAddRange.z;

				int c;
				for(int x = lower.x; x < upper.x; x += cs)
					for(int y = lower.y; y < upper.y; y += cs)
						for(int z = lower.z; z < upper.z; z += cs)
							extensionCPCache[c++] = ChunkPosition(x, y, z);
				extensionCPLength = c;
				extensionCPBias = 0;

				sort!cdCmp(cache[0..extensionCPLength]);

				isExtensionCacheSorted = true;
			}

			taskPool.put(task(&sortTask, extensionCPCache));
		}

		if(!isExtensionCacheSorted) return;

		int doAddNum;
		enum addMax = 10;

		foreach(ChunkPosition pos; extensionCPCache[extensionCPBias .. extensionCPLength])
		{
			ChunkState* getter = pos in chunkStates;
			bool absent = getter is null || *getter == ChunkState.deallocated;
			bool doAdd = absent || (isInPlayerLocalBounds(cam, pos) && *getter == ChunkState.hibernated);

			if(doAdd)
			{
				if(doAddNum > addMax) return;

				BasicChunk chunk = createChunk(pos);
				chunksTerrain[pos] = chunk;
				chunkStates[pos] = ChunkState.notLoaded;

				doAddNum++;
				chunksCreated++;
				extensionCPBias++;
			}
		}
	}

	private void manageChunkState(ref BasicChunk bc)
	{
		with(bc)
		{
			if(chunk.needsData && !chunk.isAnyMeshBlocking && chunk.readonlyRefs == 0) 
			{
				chunkLoadNeighbours(bc);
			}
			if(chunk.dataLoadCompleted)
			{
				chunkStates[position] = ChunkState.active;
				chunk.needsMesh = true;
				chunk.dataLoadCompleted = false;
				chunk.hasData = true;

				noiseCompleted++;
				noiseCompletedCounter++;
			}

			if(chunk.needsMesh && !chunk.needsData && !chunk.dataLoadBlocking && !chunk.dataLoadCompleted && chunk.readonlyRefs == 0)
			{
				if((chunk.airCount == ChunkData.chunkOverrunDimensionsCubed || 
				   chunk.solidCount == ChunkData.chunkOverrunDimensionsCubed ||
				   chunk.fluidCount == ChunkData.chunkOverrunDimensionsCubed) && !isInPlayerLocalBounds(cameraPositionChunk, bc.position)) 
				{
					chunksTerrain.remove(position);
					chunk.deinitialise();
					chunkStates[position] = ChunkState.hibernated;
					chunksHibernated++;
					return;
				}
				else
				{
					if(bc.chunk.isCompressed)
					{
						import squareone.terrain.basic.rle;
						decompressChunk(bc.chunk);
						chunksDecompressed++;
					}
					foreach(int proc; 0 .. resources.processorCount)
						resources.getProcessor(proc).meshChunk(MeshOrder(chunk, true, true, false));

					meshOrders++;
				}
				chunk.needsMesh = false;
			}

			if(isInPlayerLocalBounds(cameraPositionChunk, bc.position) && chunk.isCompressed)
			{
				import squareone.terrain.basic.rle;
				decompressChunk(bc.chunk);
				chunksDecompressed++;
			}

			if(!chunk.needsMesh && !chunk.needsData && !chunk.dataLoadBlocking && !chunk.dataLoadCompleted && chunk.readonlyRefs == 0 && !chunk.isAnyMeshBlocking && !isInPlayerLocalBounds(cameraPositionChunk, bc.position) && !chunk.isCompressed)
			{
				import squareone.terrain.basic.rle;
				compressChunk(bc.chunk);
				chunksCompressed++;
			}
		}
	}

	private void chunkLoadNeighbours(ref BasicChunk bc)
	{
		enum CSource
		{
			activeChunk,
			region,
			noise
		}

		NoiseGeneratorOrder noiseOrder = NoiseGeneratorOrder(bc.chunk, bc.position, null, true, true);
		/*CSource[26] neighbourSources;
		foreach(n; 0 .. cast(int)ChunkNeighbours.last)
		{
			ChunkNeighbours nn = cast(ChunkNeighbours)n;
			ChunkPosition offset = chunkNeighbourToOffset(nn);
			ChunkPosition np = bc.position + offset;

			ChunkState* state = np in chunkStates;
			if(state !is null && *state == ChunkState.active)
			{
				Optional!BasicChunkReadonly nc;
				mixin(ForceBorrowReadonly!("np", "nc"));

				Vector3i[2] bin = neighbourBounds[n];
				foreach(x; bin[0].x .. bin[1].x)
				{
					foreach(y; bin[0].y .. bin[1].y)
					{
						foreach(z; bin[0].z .. bin[1].z)
						{
							BlockPosition bp = np.toBlockPosition(BlockOffset(x, y, z));
							BlockOffset bcOff = bc.position.toOffset(bp);

							bc.chunk.set(bcOff.x, bcOff.y, bcOff.z, nc.unwrap.chunk.get(x, y, z));
						}
					}
				}

				continue;
			}

			noiseOrder.loadNeighbour(nn, true);
		}*/

		noiseGeneratorManager.generate(noiseOrder);
	}

	private bool isInPlayerLocalBounds(ChunkPosition camera, ChunkPosition position)
	{
		return position.x >= camera.x - settings.playerLocalRange.x && position.x < camera.x + settings.playerLocalRange.x &&
			position.y >= camera.y - settings.playerLocalRange.y && position.y < camera.y + settings.playerLocalRange.y &&
			position.z >= camera.z - settings.playerLocalRange.z && position.z < camera.z + settings.playerLocalRange.z;
	}

	private bool isChunkInBounds(ChunkPosition camera, ChunkPosition position)
	{
		return position.x >= camera.x - settings.removeRange.x && position.x < camera.x + settings.removeRange.x &&
			position.y >= camera.y - settings.removeRange.y && position.y < camera.y + settings.removeRange.y &&
			position.z >= camera.z - settings.removeRange.z && position.z < camera.z + settings.removeRange.z;
	}
}

/// Allows external entities to interact with the voxel field on a per-voxel basis.
final class VoxelInteraction
{
	private BasicTerrainManager manager;

	this(BasicTerrainManager manager)
	in(manager !is null)
	{ this.manager = manager; }

	/// Get a voxel at BlockPosition pos.
	Maybe!Voxel get(BlockPosition pos)
	{
		ChunkPosition cp;
		BlockOffset off;
		ChunkPosition.blockPosToChunkPositionAndOffset(pos, cp, off);

		return get(cp, off);
	}

	/// Get a chunk at ChunkPosition cp, and a voxel inside it at BlockOffset off.
	Maybe!Voxel get(ChunkPosition cp, BlockOffset off)
	{
		ChunkState* state = cp in manager.chunkStates;
		if(state is null) 
			return Maybe!Voxel();
		if(*state == ChunkState.deallocated || *state == ChunkState.notLoaded) 
			return Maybe!Voxel();

		BasicChunk* bc = cp in manager.chunksTerrain;
		if(bc is null)
			return Maybe!Voxel();
		if(!bc.chunk.hasData) 
			return Maybe!Voxel();

		// does not collide with readonly refs, meshers
		if(bc.chunk.needsData || bc.chunk.dataLoadBlocking || 
		   bc.chunk.dataLoadCompleted || bc.chunk.isCompressed)
			return Maybe!Voxel();

		return Maybe!Voxel(bc.chunk.get(off.x, off.y, off.z));
	}

	/// Set a voxel at BlockPosition position
	void set(Voxel voxel, BlockPosition position)
	{
		ChunkPosition cp;
		BlockOffset offset;
		ChunkPosition.blockPosToChunkPositionAndOffset(position, cp, offset);

		return set(voxel, cp, offset);
	}

	/// Set a voxel at ChunkPosition, BlockOffset
	void set(Voxel voxel, ChunkPosition cp, BlockOffset offset)
	{ voxelSetCommands.insertBack(VoxelSetOrder(cp, offset, voxel)); }

	private struct VoxelSetOrder
	{
		ChunkPosition chunkPosition;
		BlockOffset offset;
		Voxel voxel;
		this(ChunkPosition chunkPosition, BlockOffset offset, Voxel voxel) { this.chunkPosition = chunkPosition; this.offset = offset; this.voxel = voxel; }
	}

	private CyclicBuffer!VoxelSetOrder voxelSetCommands;
	private CyclicBuffer!VoxelSetOrder overrunSetCommands; // if chunk is busy, add to queue and run after

	private CyclicBuffer!BasicChunk chunksToMesh;

	/// handle all interactions
	void run()
	{
		executeSetVoxel;
		executeDeferredOverruns;

		auto length = chunksToMesh.length;
		foreach(size_t chunkID; 0 .. length)
		{
			BasicChunk bc = chunksToMesh.front;
			chunksToMesh.popFront;

			bc.chunk.needsMesh = true;
		}
	}

	/// handle direct voxel sets
	private void executeSetVoxel()
	{
		size_t length = voxelSetCommands.length;
		foreach(size_t commID; 0 .. length)
		{
			VoxelSetOrder order = voxelSetCommands.front;
			voxelSetCommands.popFront;

			// continue = discard

			ChunkState* state = order.chunkPosition in manager.chunkStates;
			if(state is null) 
				continue; // discard
			if(*state == ChunkState.notLoaded || *state == ChunkState.deallocated) 
				continue;

			BasicChunk* bc = order.chunkPosition in manager.chunksTerrain;
			if(bc is null)
				continue;

			if(!bc.chunk.hasData)
			{
				voxelSetCommands.insertBack(order);
				continue;
			}

			if(bc.chunk.needsData || bc.chunk.dataLoadBlocking || 
			   bc.chunk.dataLoadCompleted || bc.chunk.isCompressed ||
			   bc.chunk.readonlyRefs > 0 || bc.chunk.needsMesh ||
			   bc.chunk.isAnyMeshBlocking)
			{
				voxelSetCommands.insertBack(order);
				continue;
			}

			bc.chunk.dataLoadBlocking = true;
			bc.chunk.set(order.offset.x, order.offset.y, order.offset.z, order.voxel);
			bc.chunk.dataLoadBlocking = false;

			distributeOverruns(*bc, order.offset, order.voxel);

			chunksToMesh.insertBack(*bc);
		}
	}

	/// update voxels in neighbouring chunks
	private void distributeOverruns(BasicChunk host, BlockOffset blockPos, Voxel voxel)
	in {
		assert(blockPos.x >= 0 && blockPos.x < ChunkData.chunkDimensions);
		assert(blockPos.y >= 0 && blockPos.y < ChunkData.chunkDimensions);
		assert(blockPos.z >= 0 && blockPos.z < ChunkData.chunkDimensions);
	}
	do {
		if(blockPos.x == 0) {
			if(blockPos.y == 0) {
				if(blockPos.z == 0) {
					foreach(Vector3i off; chunkOffsets[0])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
				else if(blockPos.z == ChunkData.chunkDimensions - 1) {
					foreach(Vector3i off; chunkOffsets[1])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
				else {
					foreach(Vector3i off; chunkOffsets[2])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
			}
			else if(blockPos.y == ChunkData.chunkDimensions - 1) {
				if(blockPos.z == 0) {
					foreach(Vector3i off; chunkOffsets[3])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
				else if(blockPos.z == ChunkData.chunkDimensions - 1) {
					foreach(Vector3i off; chunkOffsets[4])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
				else {
					foreach(Vector3i off; chunkOffsets[5])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
			}
			else {
				if(blockPos.z == 0) {
					foreach(Vector3i off; chunkOffsets[6])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
				else if(blockPos.z == ChunkData.chunkDimensions - 1) {
					foreach(Vector3i off; chunkOffsets[7]) 
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
				else {
					foreach(Vector3i off; chunkOffsets[8])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
			}
		}
		else if(blockPos.x == ChunkData.chunkDimensions - 1) {
			if(blockPos.y == 0) {
				if(blockPos.z == 0) {
					foreach(Vector3i off; chunkOffsets[9])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
				else if(blockPos.z == ChunkData.chunkDimensions - 1) {
					foreach(Vector3i off; chunkOffsets[10])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
				else {
					foreach(Vector3i off; chunkOffsets[11])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
			}
			else if(blockPos.y == ChunkData.chunkDimensions - 1) {
				if(blockPos.z == 0) {
					foreach(Vector3i off; chunkOffsets[12])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
				else if(blockPos.z == ChunkData.chunkDimensions - 1) {
					foreach(Vector3i off; chunkOffsets[13])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
				else {
					foreach(Vector3i off; chunkOffsets[14])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
			}
			else {
				if(blockPos.z == 0) {
					foreach(Vector3i off; chunkOffsets[15])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
				else if(blockPos.z == ChunkData.chunkDimensions - 1) {
					foreach(Vector3i off; chunkOffsets[16]) 
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
				else {
					foreach(Vector3i off; chunkOffsets[17])
						setOverrunChunk(host, off, blockPos, voxel);
					return;
				}
			}
		}

		if(blockPos.y == 0) {
			if(blockPos.z == 0) {
				foreach(Vector3i off; chunkOffsets[18])
					setOverrunChunk(host, off, blockPos, voxel);
				return;
			}
			else if(blockPos.z == ChunkData.chunkDimensions - 1) {
				foreach(Vector3i off; chunkOffsets[19])
					setOverrunChunk(host, off, blockPos, voxel);
				return;
			}
			else {
				foreach(Vector3i off; chunkOffsets[20])
					setOverrunChunk(host, off, blockPos, voxel);
				return;
			}
		}
		else if(blockPos.y == ChunkData.chunkDimensions - 1) {
			if(blockPos.z == 0) {
				foreach(Vector3i off; chunkOffsets[21])
					setOverrunChunk(host, off, blockPos, voxel);
				return;
			}
			else if(blockPos.z == ChunkData.chunkDimensions - 1) {
				foreach(Vector3i off; chunkOffsets[22])
					setOverrunChunk(host, off, blockPos, voxel);
				return;
			}
			else {
				foreach(Vector3i off; chunkOffsets[23])
					setOverrunChunk(host, off, blockPos, voxel);
				return;
			}
		}

		if(blockPos.z == 0) {
			foreach(Vector3i off; chunkOffsets[24])
				setOverrunChunk(host, off, blockPos, voxel);
			return;
		}
		else if(blockPos.z == ChunkData.chunkDimensions - 1) {
			foreach(Vector3i off; chunkOffsets[25])
				setOverrunChunk(host, off, blockPos, voxel);
			return;
		}
	}

	/// wrapper that generates proper coordinates for handleChunkOverrun
	private void setOverrunChunk(BasicChunk bc, BlockOffset offset, BlockOffset blockPosLocal, Voxel voxel)
	{
		ChunkPosition newCP = ChunkPosition(bc.position.x + offset.x, bc.position.y + offset.y, bc.position.z + offset.z);
		BlockOffset newP = blockPosLocal + (-offset * ChunkData.chunkDimensions);
		handleChunkOverrun(newCP, newP, voxel);
	}

	/// if chunk is available, set its overrun, otherwise this will defer the command to next frame.
	private bool handleChunkOverrun(ChunkPosition cp, BlockOffset pos, Voxel voxel)
	{
		bool deferComm()
		{
			VoxelSetOrder o;
			o.chunkPosition = cp;
			o.offset = pos;
			o.voxel = voxel;
			overrunSetCommands.insertBack(o);
			return false;
		}

		ChunkState* state = cp in manager.chunkStates;
		if(state is null)
			return false;
		if(*state == ChunkState.notLoaded || *state == ChunkState.deallocated)
			return false;

		BasicChunk* bc = cp in manager.chunksTerrain;
		if(bc is null) 
			return false;
		if(!bc.chunk.hasData)
			return deferComm;

		if(bc.chunk.needsData || bc.chunk.dataLoadBlocking || 
		   bc.chunk.dataLoadCompleted || bc.chunk.isCompressed ||
		   bc.chunk.readonlyRefs > 0 || bc.chunk.needsMesh ||
		   bc.chunk.isAnyMeshBlocking)
			return deferComm;

		bc.chunk.dataLoadBlocking = true;
		bc.chunk.set(pos.x, pos.y, pos.z, voxel);
		bc.chunk.dataLoadBlocking = false;

		chunksToMesh.insertBack(*bc);

		return true;
	}

	/// handle all deferred voxel sets
	private void executeDeferredOverruns()
	{
		size_t length = overrunSetCommands.length;
		foreach(size_t commID; 0 .. length)
		{
			VoxelSetOrder o = overrunSetCommands.front;
			overrunSetCommands.popFront;

			handleChunkOverrun(o.chunkPosition, o.offset, o.voxel);
		}
	}
}

final class ChunkInteraction
{
	BasicTerrainManager manager;

	this(BasicTerrainManager manager)
	in(manager !is null)
	{
		this.manager = manager;
	}

	Maybe!BasicChunk borrow(ChunkPosition cp)
	{
		ChunkState* state = cp in manager.chunkStates;
		if(state is null)
			return Maybe!BasicChunk();
		if(*state == ChunkState.notLoaded || *state == ChunkState.deallocated)
			return Maybe!BasicChunk();

		BasicChunk* bc = cp in manager.chunksTerrain;
		if(bc is null)
			return Maybe!BasicChunk();
		if(bc.chunk.needsData || bc.chunk.dataLoadBlocking || 
		   bc.chunk.dataLoadCompleted || bc.chunk.isCompressed ||
		   bc.chunk.readonlyRefs > 0 || bc.chunk.needsMesh ||
		   bc.chunk.isAnyMeshBlocking)
			return Maybe!BasicChunk();

		bc.chunk.dataLoadBlocking = true;

		return Maybe!BasicChunk(*bc);
	}

	Maybe!BasicChunkReadonly borrowReadonly(ChunkPosition cp)
	{
		ChunkState* state = cp in manager.chunkStates;
		if(state is null)
			return Maybe!BasicChunkReadonly();
		if(*state == ChunkState.notLoaded || *state == ChunkState.deallocated)
			return Maybe!BasicChunkReadonly();

		BasicChunk* bc = cp in manager.chunksTerrain;
		if(bc is null)
			return Maybe!BasicChunkReadonly();
		if(bc.chunk.needsData || bc.chunk.dataLoadBlocking || 
		   bc.chunk.dataLoadCompleted || bc.chunk.isCompressed)
			return Maybe!BasicChunkReadonly();

		BasicChunkReadonly ro = BasicChunkReadonly(bc.chunk, bc.position, manager);
		bc.chunk.incrementReadonlyRef;

		return Maybe!BasicChunkReadonly(ro);
	}

	void give(BasicChunk bc)
	{
		if(bc.chunk.dataLoadBlocking)
		{
			bc.chunk.dataLoadBlocking = false;
			bc.chunk.dataLoadCompleted = true;
		}
	}

	void give(BasicChunkReadonly bcr)
	{
		bcr.chunk.decrementReadonlyRef;
	}
}

/*class ChunkLoadNeighbourOrder
{
	private Fiber fiber;

	BasicChunk bc;
	BasicTerrainManager manager;
	invariant { assert(manager !is null); }

	this(BasicTerrainManager m)
	{
		manager = m;
		fiber = new Fiber(&internal);
	}

	this(BasicTerrainManager m, BasicChunk bc)
	{
		this(m);
		run(bc);
	}

	void run(BasicChunk bc)
	{
		this.bc = bc;
		fiber.call;
	}

	private void internal()
	{
		enum CSource
		{
			activeChunk,
			region,
			noise
		}

		NoiseGeneratorOrder noiseOrder = NoiseGeneratorOrder(bc.chunk, bc.position, null);
		CSource[26] neighbourSources;
		foreach(n; 0 .. cast(int)ChunkNeighbours.last)
		{
			ChunkNeighbours nn = cast(ChunkNeighbours)n;
			ChunkPosition offset = chunkNeighbourToOffset(nn);
			ChunkPosition np = bc.position + offset;

			BasicTerrainManager.ChunkState* state = np in manager.chunkStates;
			if(state !is null && *state == BasicTerrainManager.ChunkState.active)
			{
				Optional!BasicChunk nc;
				mixin(ForceBorrowScope!("np", "nc", true));

				Vector3i[2] bin = neighbourBounds[n];
				foreach(x; bin[0].x .. bin[1].x)
				{
					foreach(y; bin[0].y .. bin[1].y)
					{
						foreach(z; bin[0].z .. bin[1].z)
						{
							BlockPosition bp = np.toBlockPosition(BlockOffset(x, y, z));
							BlockOffset bcOff = bc.position.toOffset(bp);

							bc.chunk.set(bcOff.x, bcOff.y, bcOff.z, nc.unwrap.chunk.get(x, y, z));
						}
					}
				}

				continue;
			}

			noiseOrder.loadNeighbour(nn, true);
		}

		noiseOrder.loadChunk = true;

		manager.noiseGeneratorManager.generate(noiseOrder);
	}
}*/

private immutable Vector3i[][] chunkOffsets = [
	// Nx Ny Nz
	[Vector3i(-1, 0, 0), Vector3i(0, -1, 0), Vector3i(0, 0, -1), Vector3i(-1, -1, 0), Vector3i(-1, 0, -1), Vector3i(0, -1, -1), Vector3i(-1, -1, -1)],
	// Nx Ny Pz
	[Vector3i(-1, 0, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(-1, -1, 0), Vector3i(-1, 0, 1), Vector3i(0, -1, 1), Vector3i(-1, -1, 1)],
	// Nx Ny 
	[Vector3i(-1, 0, 0), Vector3i(0, -1, 0), Vector3i(-1, -1, 0)],
	// Nx Py Nz
	[Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(-1, 1, 0), Vector3i(-1, 0, -1), Vector3i(0, 1, -1), Vector3i(-1, 1, -1)],
	// Nx Py Pz
	[Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(-1, 1, 0), Vector3i(-1, 0, 1), Vector3i(0, 1, 1), Vector3i(-1, 1, 1)],
	// Nx Py
	[Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(-1, 1, 0)],
	// Nx Nz
	[Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(-1, 0, -1)],
	// Nx Pz
	[Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 1)],
	// Nx
	[Vector3i(-1, 0, 0)],
	// Px Ny Nz
	[Vector3i(1, 0, 0), Vector3i(0, -1, 0), Vector3i(0, 0, -1), Vector3i(1, -1, 0), Vector3i(1, 0, -1), Vector3i(0, -1, -1), Vector3i(1, -1, -1)],
	// Px Ny Pz
	[Vector3i(1, 0, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(1, -1, 0), Vector3i(1, 0, 1), Vector3i(0, -1, 1), Vector3i(1, -1, 1)],
	// Px Ny 
	[Vector3i(1, 0, 0), Vector3i(0, -1, 0), Vector3i(1, -1, 0)],
	// Px Py Nz
	[Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(1, 1, 0), Vector3i(1, 0, -1), Vector3i(0, 1, -1), Vector3i(1, 1, -1)],
	// Px Py Pz
	[Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 1, 0), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)],
	// Px Py
	[Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0)],
	// Nx Nz
	[Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, -1)],
	// Nx Pz
	[Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)],
	// Px
	[Vector3i(1, 0, 0)],
	// Ny Nz
	[Vector3i(0, -1, 0), Vector3i(0, 0, -1), Vector3i(0, -1, -1)],
	// Ny Pz
	[Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, -1, 1)],
	// Ny
	[Vector3i(0, -1, 0)],
	// Py Nz
	[Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 1, -1)],
	// Py Pz
	[Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 1)],
	// Py
	[Vector3i(0, 1, 0)],
	// Nz
	[Vector3i(0, 0, -1)],
	// Pz
	[Vector3i(0, 0, 1)]
];

/*template ForceBorrow(string chunkPosName, string basicChunkName = "bc")
{
	const char[] ForceBorrow = "do " ~ basicChunkName ~ " = chunkSys.borrow(" ~ chunkPosName ~ "); while(" ~ basicChunkName ~ ".unwrap is null); ";
}*/

template ForceBorrowScope(string chunkPosName, string basicChunkName = "bc", bool outer = false, string man = "manager")
{
	const char[] ForceBorrowScope = "do " ~ basicChunkName ~ " = " ~ (outer == true ? man : "this") ~ ".chunkSys.borrow(" ~ chunkPosName ~ "); while(" ~ basicChunkName ~ ".unwrap is null); scope(exit) " ~ (outer == true ? man : "this") ~ ".chunkSys.give(*" ~ basicChunkName ~ ".unwrap); ";
}

template ForceBorrowReadonly(string chunkPosName, string basicChunkName = "bc", bool outer = false, string man = "manager")
{
	const char[] ForceBorrowReadonly = "do " ~ basicChunkName ~ " = " ~ (outer == true ? man : "this") ~ ".chunkSys.borrowReadonly(" ~ chunkPosName ~ "); while(" ~ basicChunkName ~ ".unwrap is null); ";
}