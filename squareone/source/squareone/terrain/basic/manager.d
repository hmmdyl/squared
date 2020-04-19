module squareone.terrain.basic.manager;

import squareone.terrain.basic.chunk;
import squareone.terrain.gen.noisegen;
import squareone.terrain.gen.generators;
import squareone.voxel;
import moxane.core;
import moxane.graphics.redo;
import moxane.utils.maybe;

import dlib.math;
import dlib.geometry : Frustum, Sphere;
import std.math : sqrt;
import std.datetime.stopwatch;
import std.parallelism;
import containers;
import core.thread;

final class TerrainRenderer : IDrawable
{
	bool culling;

	BasicTerrainManager btm;
	invariant { assert(btm !is null); }

	this(BasicTerrainManager btm, bool culling = true)
	{ this.btm = btm; this.culling = culling; }

	float renderTime = 0f;
	float prepareTime = 0f;

	private size_t translucentCount;

	void draw(Pipeline pipeline, ref LocalContext lc, ref PipelineStatics stats) @trusted
	{
		Matrix4f vp = lc.camera.projection * lc.camera.viewMatrix;
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
			p.beginDraw(pipeline, lc);
			trueSw.stop;
			scope(exit) p.endDraw(pipeline, lc);

			if(!culling)
			{
				foreach(BasicChunk chunk; btm.chunksTerrain)
					p.drawChunk(chunk, lc, stats);
			}
			else
			{
				bool shouldRender(BasicChunk chunk)
				{
					immutable Vector3f chunkPosReal = chunk.position.toVec3f;
					immutable float dimReal = ChunkData.chunkDimensionsMetres * chunk.blockskip;
					immutable Vector3f center = Vector3f(chunkPosReal.x + dimReal * 0.5f, chunkPosReal.y + dimReal * 0.5f, chunkPosReal.z + dimReal * 0.5f);
					immutable float radius = sqrt(dimReal ^^ 2 + dimReal ^^ 2);
					Sphere s = Sphere(center, radius);

					return frustum.intersectsSphere(s);
				}

				foreach(BasicChunk chunk; btm.chunksTerrain)
				{
					if(!shouldRender(chunk)) continue;
					p.drawChunk(chunk, lc, stats);
				}
			}
		}
	}
}

version(OLD)
{
final class BasicTerrainRenderer : IRenderable
{
	bool culling;

	BasicTerrainManager btm;
	invariant { assert(btm !is null); }

	this(BasicTerrainManager btm, bool culling = true)
	{ this.btm = btm; this.culling = culling; }

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

			if(!culling)
			{
				foreach(BasicChunk chunk; btm.chunksTerrain)
					p.render(chunk, lc, drawCalls, numVerts);
			}
			else
			{
				bool shouldRender(BasicChunk chunk)
				{
					immutable Vector3f chunkPosReal = chunk.position.toVec3f;
					immutable float dimReal = ChunkData.chunkDimensionsMetres * chunk.blockskip;
					immutable Vector3f center = Vector3f(chunkPosReal.x + dimReal * 0.5f, chunkPosReal.y + dimReal * 0.5f, chunkPosReal.z + dimReal * 0.5f);
					immutable float radius = sqrt(dimReal ^^ 2 + dimReal ^^ 2);
					Sphere s = Sphere(center, radius);

					return frustum.intersectsSphere(s);
				}

				foreach(BasicChunk chunk; btm.chunksTerrain)
				{
					if(!shouldRender(chunk)) continue;

					uint dc;
					p.render(chunk, lc, dc, numVerts);
					drawCallsPhys += dc;
					drawCalls += dc;
				}
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
	NoiseGeneratorManager2!NoiseGeneratorOrder noiseGeneratorManager;

	VoxelInteraction voxelInteraction;
	ChunkInteraction chunkInteraction;

	uint chunksCreated, chunksHibernated, chunksRemoved, chunksCompressed, chunksDecompressed;
	uint noiseCompleted, meshOrders;

	private StopWatch oneSecondSw;
	private uint noiseCompletedCounter;
	uint noiseCompletedSecond;

	private Channel!MeshOrder[IProcessor] meshQueues;
	private IMesher[][IProcessor] meshers;
	private bool shouldKickMesher;

	this(Moxane moxane, BasicTMSettings settings)
	{
		this.moxane = moxane;
		this.settings = settings;
		resources = settings.resources;

		foreach(procID; 0 .. resources.processorCount)
		{
			IProcessor processor = resources.getProcessor(procID);
			meshQueues[processor] = new Channel!MeshOrder;
			meshers[processor] = new IMesher[](processor.minMeshers);
			foreach(mesherID; 0 .. processor.minMeshers)
				meshers[processor][mesherID] = processor.requestMesher(meshQueues[processor]);
		}

		voxelInteraction = new VoxelInteraction(this);
		chunkInteraction = new ChunkInteraction(this);

		Log log = moxane.services.getAOrB!(VoxelLog, Log);

		noiseGeneratorManager = new NoiseGeneratorManager2!NoiseGeneratorOrder(resources, log, (NoiseGeneratorManager2!NoiseGeneratorOrder m, Resources r, IChannel!NoiseGeneratorOrder o) => new DefaultNoiseGeneratorV1(m, r, o));
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
		noiseGeneratorManager.managerTick(moxane.deltaTime);
		manageChunks;
	}

	private void manageChunks()
	{
		shouldKickMesher = false;

		const ChunkPosition cp = ChunkPosition.fromVec3f(cameraPosition);
		cameraPositionPreviousChunk = cameraPositionChunk;
		cameraPositionChunk = cp;

		kickMeshers;
		scope(success) kickMeshers;

		//addChunksLocal(cp);
		addChunksExtension(cp, cameraPosition);

		voxelInteraction.run;

		foreach(ref BasicChunk bc; chunksTerrain)
			manageChunkState(bc);
		foreach(ref BasicChunk bc; chunksTerrain)
			removeChunkHandler(bc, cp);

		if(oneSecondSw.peek.total!"seconds"() >= 1)
		{
			oneSecondSw.reset;
			noiseCompletedSecond = noiseCompletedCounter;
			noiseCompletedCounter = 0;
		}
	}

	private BasicChunk createChunk(ChunkPosition pos, bool needsData = true)
	{
		auto c = new BasicChunk(resources);
		c.position = pos;
		c.initialise;
		c.needsData = needsData;
		c.lod = 0;
		c.blockskip = 2 ^^ c.lod;
		c.isCompressed = false;
		return c;
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
					auto newCp = ChunkPosition(x, y, z);

					ChunkState* getter = newCp in chunkStates;
					bool absent = getter is null || *getter == ChunkState.deallocated;
					bool doAdd = absent || (isInPlayerLocalBounds(cp, newCp) && *getter == ChunkState.hibernated);

					if(doAdd)
					{
						auto chunk = createChunk(newCp);
						chunksTerrain[newCp] = chunk;
						chunkStates[newCp] = ChunkState.notLoaded;
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
			if(chunk.needsData || chunk.dataLoadBlocking || chunk.dataLoadCompleted ||
			   chunk.needsMesh || chunk.isAnyMeshBlocking || chunk.readonlyRefs > 0)
				chunk.pendingRemove = true;
			else
			{
				foreach(int proc; 0 .. resources.processorCount)
					resources.getProcessor(proc).removeChunk(chunk);

				chunksTerrain.remove(chunk.position);
				chunkStates.remove(chunk.position);
				chunk.deinitialise();

				//destroy(chunk);

				delete chunk;

				chunksRemoved++;
			}
		}
	}

	private StopWatch addExtensionSortSw;
	private bool isExtensionCacheSorted;
	private ChunkPosition[] extensionCPCache;
	private size_t extensionCPBias, extensionCPLength;

	private void addChunksExtension(const ChunkPosition cam, const Vector3f camReal)
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
				immutable camf = camReal.lengthsqr;

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

	private void manageChunkState(ref BasicChunk chunk)
	{
		if(chunk.needsData && !chunk.isAnyMeshBlocking && chunk.readonlyRefs == 0) 
		{
			chunkLoadNeighbours(chunk);
		}
		if(chunk.dataLoadCompleted)
		{
			chunkStates[chunk.position] = ChunkState.active;
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
				chunk.fluidCount == ChunkData.chunkOverrunDimensionsCubed) && !isInPlayerLocalBounds(cameraPositionChunk, chunk.position)) 
			{
				chunksTerrain.remove(chunk.position);
				chunk.deinitialise();
				chunkStates[chunk.position] = ChunkState.hibernated;
				chunksHibernated++;

				delete chunk;

				return;
			}
			else
			{
				if(chunk.isCompressed)
				{
					import squareone.terrain.basic.rle;
					decompressChunk(chunk);
					chunksDecompressed++;
				}
				meshChunks(MeshOrder(chunk, true, true, false));
				if(!shouldKickMesher)
				{
					shouldKickMesher = true;
					kickMeshers;
				}
					
				meshOrders++;
			}
			chunk.needsMesh = false;
		}

		if(isInPlayerLocalBounds(cameraPositionChunk, chunk.position) && chunk.isCompressed)
		{
			import squareone.terrain.basic.rle;
			decompressChunk(chunk);
			chunksDecompressed++;
		}

		if(!chunk.needsMesh && !chunk.needsData && !chunk.dataLoadBlocking && !chunk.dataLoadCompleted && chunk.readonlyRefs == 0 && !chunk.isAnyMeshBlocking && !isInPlayerLocalBounds(cameraPositionChunk, chunk.position) && !chunk.isCompressed)
		{
			import squareone.terrain.basic.rle;
			compressChunk(chunk);
			chunksCompressed++;
		}
	}

	private void kickMeshers()
	{
		foreach(IProcessor processor, IMesher[] meshersForProcessor; meshers)
		{
			foreach(size_t id, IMesher mesher; meshersForProcessor)
			{
				if(mesher.parked)
					mesher.kick;
				if(mesher.terminated)
				{
					import std.algorithm.mutation : remove;
					remove(meshersForProcessor, id);
					processor.returnMesher(mesher);
				}
			}
		}
	}

	private void terminateMeshers()
	{
		foreach(IProcessor processor, IMesher[] meshersForProcessor; meshers)
		{
			foreach(size_t id, IMesher mesher; meshersForProcessor)
			{
				mesher.terminate;
				processor.returnMesher(mesher);
				import std.algorithm.mutation : remove;
				remove(meshersForProcessor, id);
			}
		}
	}

	private void meshChunks(MeshOrder order)
	{
		foreach(processor, channel; meshQueues)
		{
			order.chunk.meshBlocking(true, processor.id);
			channel.send(order);
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

		NoiseGeneratorOrder noiseOrder = NoiseGeneratorOrder(bc, bc.position, null, true, true);
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

		noiseGeneratorManager.generateChunk(noiseOrder);
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
		if(!bc.hasData) 
			return Maybe!Voxel();

		// does not collide with readonly refs, meshers
		if(bc.needsData || bc.dataLoadBlocking || 
		   bc.dataLoadCompleted || bc.isCompressed)
			return Maybe!Voxel();

		return Maybe!Voxel(bc.get(off.x, off.y, off.z));
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

			bc.needsMesh = true;
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

			if(!bc.hasData)
			{
				voxelSetCommands.insertBack(order);
				continue;
			}

			if(bc.needsData || bc.dataLoadBlocking || 
			   bc.dataLoadCompleted || bc.isCompressed ||
			   bc.readonlyRefs > 0 || bc.needsMesh ||
			   bc.isAnyMeshBlocking)
			{
				voxelSetCommands.insertBack(order);
				continue;
			}

			bc.dataLoadBlocking = true;
			bc.set(order.offset.x, order.offset.y, order.offset.z, order.voxel);
			bc.dataLoadBlocking = false;

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
		if(!bc.hasData)
			return deferComm;

		if(bc.needsData || bc.dataLoadBlocking || 
		   bc.dataLoadCompleted || bc.isCompressed ||
		   bc.readonlyRefs > 0 || bc.needsMesh ||
		   bc.isAnyMeshBlocking)
			return deferComm;

		bc.dataLoadBlocking = true;
		bc.set(pos.x, pos.y, pos.z, voxel);
		bc.dataLoadBlocking = false;

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

	BasicChunk borrow(ChunkPosition cp)
	{
		ChunkState* state = cp in manager.chunkStates;
		if(state is null)
			return null;
		if(*state == ChunkState.notLoaded || *state == ChunkState.deallocated)
			return null;

		BasicChunk* bc = cp in manager.chunksTerrain;
		if(bc is null)
			return null;
		if(bc.needsData || bc.dataLoadBlocking || 
		   bc.dataLoadCompleted || bc.isCompressed ||
		   bc.readonlyRefs > 0 || bc.needsMesh ||
		   bc.isAnyMeshBlocking)
			return null;

		bc.dataLoadBlocking = true;

		return *bc;
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
		if(bc.needsData || bc.dataLoadBlocking || 
		   bc.dataLoadCompleted || bc.isCompressed)
			return Maybe!BasicChunkReadonly();

		BasicChunkReadonly ro = BasicChunkReadonly(*bc);
		bc.incrementReadonlyRef;

		return Maybe!BasicChunkReadonly(ro);
	}

	void give(BasicChunk bc)
	{
		if(bc.dataLoadBlocking)
		{
			bc.dataLoadBlocking = false;
			bc.dataLoadCompleted = true;
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