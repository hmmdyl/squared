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
import optional;
import containers;
import core.thread;

final class BasicTerrainRenderer : IRenderable
{
	BasicTerrainManager btm;
	invariant { assert(btm !is null); }

	this(BasicTerrainManager btm)
	{ this.btm = btm; }

	void render(Renderer renderer, ref LocalContext lc, out uint drawCalls, out uint numVerts)
	{
		Matrix4f vp = lc.projection * lc.view;
		Frustum frustum = Frustum(vp);

		const Vector3i min = btm.cameraPositionChunk.toVec3i - btm.settings.removeRange;
		const Vector3i max = btm.cameraPositionChunk.toVec3i + (btm.settings.removeRange + 1);

		synchronized(btm.chunkDefer)
		{
			foreach(proc; 0 .. btm.resources.processorCount)
			{
				IProcessor p = btm.resources.getProcessor(proc);
				p.prepareRender(renderer);
				scope(exit) p.endRender;

				/+foreach(ref BasicChunk chunk; btm.chunksTerrain)
					p.render(chunk.chunk, lc, drawCalls, numVerts);+/

				enum skipSize = 4;
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
						BasicChunk* chunk = ChunkPosition(cix, ciy, ciz) in btm.chunkDefer.chunks;
						if(chunk is null)
							continue;

						p.render(chunk.chunk, lc, drawCalls, numVerts);
					}
				}
			}
		}
	}
}

struct BasicTMSettings
{
	Vector3i addRange, extendedAddRange, removeRange;
	Resources resources;
}

enum ChunkState
{
	deallocated,
	/// memory is assigned, but no voxel data.
	notLoaded,
	active
}

private final class BTMChunkDefer
{
	BasicChunk[ChunkPosition] chunks;

	struct Item 
	{
		BasicChunk val;
		ChunkPosition key;
		this(BasicChunk val, ChunkPosition key) { this.val = val; this.key = key; }
	}

	UnrolledList!Item additions;
	UnrolledList!Item removals;

	void update()
	{
		synchronized(this)
		{
			while(additions.length > 0)
			{
				Item i = additions.front;
				additions.popFront;

				chunks[i.key] = i.val;
			}

			while(removals.length > 0)
			{
				Item i = removals.front;
				removals.popFront;

				chunks.remove(i.key);

				i.val.chunk.deinitialise;

				// TODO: handle memory recycle of chunk
			}
		}
	}

	void addition(ChunkPosition pos, BasicChunk chunk) { synchronized(this) additions ~= Item(chunk, pos); }
	void removal(ChunkPosition pos, BasicChunk chunk) { synchronized(this) removals ~= Item(chunk, pos); }
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
	ChunkPosition cameraPositionChunk;
	NoiseGeneratorManager noiseGeneratorManager;

	VoxelInteraction voxelInteraction;
	ChunkInteraction chunkInteraction;
	BTMChunkDefer chunkDefer;

	private Thread updateWorkerThread;

	this(Moxane moxane, BasicTMSettings settings)
	{
		this.moxane = moxane;
		this.settings = settings;
		resources = settings.resources;

		voxelInteraction = new VoxelInteraction(this);
		chunkInteraction = new ChunkInteraction(this);
		chunkDefer = new BTMChunkDefer;

		noiseGeneratorManager = new NoiseGeneratorManager(resources, 4, () => new DefaultNoiseGenerator(moxane), 0);
		auto ecpcNum = (settings.extendedAddRange.x * 2 + 1) * (settings.extendedAddRange.y * 2 + 1) * (settings.extendedAddRange.z * 2 + 1);
		extensionCPCache = new ChunkPosition[ecpcNum];

		updateWorkerThread = new Thread(&updateWorker);
		updateWorkerThread.isDaemon = true;
		updateWorkerThread.start;
	}

	~this()
	{
		destroy(noiseGeneratorManager);
	}

	void update()
	{
		chunkDefer.update;
	}

	private void updateWorker()
	{
		try
		{
			while(true)
				manageChunks;
		}
		catch(Error e)
		{
			moxane.services.get!Log().write(Log.Severity.panic, "Manager failed! " ~ e.toString);
		}
	}

	private void manageChunks()
	{
		StopWatch sw = StopWatch(AutoStart.yes);

		const ChunkPosition cp = ChunkPosition.fromVec3f(cameraPosition);
		cameraPositionChunk = cp;

		addChunksLocal(cp);
		addChunksExtension(cp);

		voxelInteraction.run;

		noiseGeneratorManager.pumpCompletedQueue;
		foreach(ref BasicChunk bc; chunksTerrain)
		{
			manageChunkState(bc);
			removeChunkHandler(bc, cp);
		}

		sw.stop;
		//import std.conv : to;
		//moxane.services.get!Log().write(Log.Severity.info, to!string(sw.peek.total!"nsecs" / 1_000_000f));
	}

	private BasicChunk createChunk(ChunkPosition pos, bool needsData = true)
	{
		Chunk c = new Chunk(resources);
		c.initialise;
		c.needsData = needsData;
		c.lod = 0;
		c.blockskip = 1;
		return BasicChunk(c, pos);
	}

	private void addChunksLocal(const ChunkPosition cp)
	{
		Vector3i lower = Vector3i(
			cp.x - settings.addRange.x,
			cp.y - settings.addRange.y,
			cp.z - settings.addRange.z);
		Vector3i upper = Vector3i(
			cp.x + settings.addRange.x,
			cp.y + settings.addRange.y,
			cp.z + settings.addRange.z);

		int numChunksAdded;

		for(int x = lower.x; x < upper.x; x++)
		{
			for(int y = lower.y; y < upper.y; y++)
			{
				for(int z = lower.z; z < upper.z; z++)
				{
					if(numChunksAdded > 1000) return;

					auto newCp = ChunkPosition(x, y, z);

					ChunkState* getter = newCp in chunkStates;
					bool doAdd = getter is null || *getter == ChunkState.deallocated;

					if(doAdd)
					{
						auto chunk = createChunk(newCp);
						chunksTerrain[newCp] = chunk;
						chunkStates[newCp] = ChunkState.notLoaded;
						chunkDefer.addition(newCp, chunk);
					}

					numChunksAdded++;
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
				chunkDefer.removal(chunk.position, chunk);
				//chunk.chunk.deinitialise(); CHUNK DEFER
			}
		}
	}

	private StopWatch addExtensionSortSw;
	private bool isExtensionCacheSorted;
	private ChunkPosition[] extensionCPCache;

	private void addChunksExtension(const ChunkPosition cam)
	{
		bool doSort;

		if(!addExtensionSortSw.running)
		{
			addExtensionSortSw.start;
			doSort = true;
		}
		if(addExtensionSortSw.peek.total!"msecs"() >= 300)
		{
			addExtensionSortSw.reset;
			addExtensionSortSw.start;
			doSort = true;
		}

		if(doSort)
		{
			isExtensionCacheSorted = false;

			Vector3i lower;
			lower.x = cam.x - settings.extendedAddRange.x;
			lower.y = cam.y - settings.extendedAddRange.y;
			lower.z = cam.z - settings.extendedAddRange.z;
			Vector3i upper;
			upper.x = cam.x + settings.extendedAddRange.x;
			upper.y = cam.y + settings.extendedAddRange.y;
			upper.z = cam.z + settings.extendedAddRange.z;

			int c;
			foreach(int x; lower.x .. upper.x)
				foreach(int y; lower.y .. upper.y)
					foreach(int z; lower.z .. upper.z)
						extensionCPCache[c++] = ChunkPosition(x, y, z);

			float camf = cam.toVec3f.length;

			auto cdCmp(ChunkPosition x, ChunkPosition y)
			{
				float x1 = x.toVec3f.length - camf;
				float y1 = y.toVec3f.length - camf;
				return x1 < y1;
			}

			void sortTask(ChunkPosition[] cache)
			{
				import std.algorithm.sorting : sort;
				sort!cdCmp(cache);
				isExtensionCacheSorted = true;
			}

			taskPool.put(task(&sortTask, extensionCPCache));
		}

		if(!isExtensionCacheSorted) return;

		int doAddNum;
		enum addMax = 250;

		foreach(ChunkPosition pos; extensionCPCache)
		{
			ChunkState* getter = pos in chunkStates;
			bool doAdd = getter is null || *getter == ChunkState.deallocated;

			if(doAdd)
			{
				if(doAddNum > addMax) return;

				BasicChunk chunk = createChunk(pos);
				chunksTerrain[pos] = chunk;
				chunkStates[pos] = ChunkState.notLoaded;
				chunkDefer.addition(pos, chunk);

				doAddNum++;
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
			}

			if(chunk.needsMesh && !chunk.needsData && !chunk.dataLoadBlocking && !chunk.dataLoadCompleted && chunk.readonlyRefs == 0)
			{
				if(chunk.airCount == ChunkData.chunkOverrunDimensionsCubed || 
				   chunk.solidCount == ChunkData.chunkOverrunDimensionsCubed ||
				   chunk.fluidCount == ChunkData.chunkOverrunDimensionsCubed) 
				{
					chunksTerrain.remove(position);
					chunk.deinitialise();
					chunkStates[position] = ChunkState.notLoaded;
					//chunksHibernated++;
					return;
				}
				else
				{
					foreach(int proc; 0 .. resources.processorCount)
						resources.getProcessor(proc).meshChunk(MeshOrder(chunk, true, true, false));
				}
				chunk.needsMesh = false;
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

	private bool isChunkInBounds(ChunkPosition camera, ChunkPosition position)
	{
		return position.x >= camera.x - settings.removeRange.x && position.x < camera.x + settings.removeRange.x &&
			position.y >= camera.y - settings.removeRange.y && position.y < camera.y + settings.removeRange.y &&
			position.z >= camera.z - settings.removeRange.z && position.z < camera.z + settings.removeRange.z;
	}

	/+struct ChunkInteraction
	{
		private BasicTerrainManager m;
		invariant { assert(m !is null); }

		@property bool isPresent(ChunkPosition pos) const
		{
			const ChunkState* state = pos in m.chunkStates;
			if(state is null)
				return false;
			else if(*state == ChunkState.deallocated || *state == ChunkState.notLoaded)
				return false;
			else return true;
		}

		Optional!BasicChunk borrow(ChunkPosition pos)
		{
			ChunkState* state = pos in m.chunkStates;
			if(state is null || *state == ChunkState.deallocated || *state == ChunkState.notLoaded)
				return no!BasicChunk;

			BasicChunk* chunk = pos in m.chunksTerrain;
			if(chunk is null)
				return no!BasicChunk;
			if(chunk.chunk.needsData || chunk.chunk.dataLoadBlocking || chunk.chunk.dataLoadCompleted || chunk.chunk.needsMesh || chunk.chunk.isAnyMeshBlocking || chunk.chunk.readonlyRefs > 0)
				return no!BasicChunk;
			chunk.chunk.dataLoadBlocking = true;

			return Optional!BasicChunk(*chunk);
		}

		void give(BasicChunk chunk)
		in { assert((chunk.position in m.chunksTerrain) !is null); }
		do { chunk.chunk.dataLoadBlocking = false; }

		Optional!BasicChunkReadonly borrowReadonly(ChunkPosition pos)
		{
			ChunkState* state = pos in m.chunkStates;
			if(state is null || *state == ChunkState.deallocated || *state == ChunkState.notLoaded)
				return no!BasicChunkReadonly;

			BasicChunk* chunk = pos in m.chunksTerrain;
			if(chunk is null)
				return no!BasicChunkReadonly;
			if(chunk.chunk.needsData || chunk.chunk.dataLoadBlocking || chunk.chunk.dataLoadCompleted || chunk.chunk.needsMesh || chunk.chunk.isAnyMeshBlocking)
				return no!BasicChunkReadonly;
			chunk.chunk.incrementReadonlyRef;

			return Optional!BasicChunkReadonly(BasicChunkReadonly(chunk.chunk, pos, m));
		}

		void giveReadonly(ref BasicChunkReadonly chunk)
		{
			chunk.chunk.decrementReadonlyRef;
		}
	}
	ChunkInteraction* chunkSys;

	struct VoxelInteraction
	{
		private BasicTerrainManager manager;
		invariant { assert(manager !is null); }

		EventWaiter!VoxelSetFailure* onSetFailure;

		this(BasicTerrainManager m)
		{
			this.manager = m;
			this.onSetFailure = &m.onSetFailure;
		}

		Optional!Voxel get(long x, long y, long z)
		{
			ChunkPosition cp;
			BlockOffset offset;
			ChunkPosition.blockPosToChunkPositionAndOffset(Vector!(long, 3)(x, y, z), cp, offset);
			return get(cp, offset);
		}

		Optional!Voxel get(ChunkPosition chunkPosition, BlockOffset cp)
		{
			ChunkState* state = chunkPosition in manager.chunkStates;
			if(state is null) return no!Voxel;
			if(*state != ChunkState.active) return no!Voxel;

			BasicChunk* bc = chunkPosition in manager.chunksTerrain;
			if(bc is null) return no!Voxel;
			if(!bc.chunk.hasData) return no!Voxel;

			return Optional!Voxel(bc.chunk.get(cp.x, cp.y, cp.z));
		}

		void set(Voxel voxel, BlockPosition blockPosition, bool forceLoad = false)
		{
			VoxelSetCommand comm = {
 				voxel : voxel,
				blockPosition : blockPosition,
				forceLoadChunk : forceLoad
			};
			manager.setBlockCommands.insertBack(comm);
		}
	}
	VoxelInteraction* voxel;

	// OVERRUN QUEUE

	private struct OverrunSetCommand
	{
		ChunkPosition cp;
		BlockOffset position;
		Voxel voxel;
	}
	private DynamicArray!OverrunSetCommand setOverrunCommands;

	private void executeSetOverruns()
	{
		size_t originalLength = setOverrunCommands.length;
		size_t index;
		foreach(size_t i; 0 .. originalLength)
		{
			OverrunSetCommand comm = setOverrunCommands[index];

			if(!chunkSys.isPresent(comm))
				setOverrunCommands.remove(index);
			else
			{

			}
		}
	}

	// VOXEL SET QUEUE

	private struct VoxelSetCommand
	{
		Voxel voxel;
		BlockPosition blockPosition;
		bool forceLoadChunk;
	}
	private CyclicBuffer!VoxelSetCommand setBlockCommands;

	struct VoxelSetFailure
	{
		Voxel voxel;
		BasicChunk* chunk;
		Vector!(long, 3) blockPos;
	}
	private EventWaiter!VoxelSetFailure onSetFailure;

	private void executeSetVoxels()
	{
		bool executeSetVoxel(VoxelSetCommand c)
		{
			BlockOffset blockOffset;
			ChunkPosition chunkPos;
			ChunkPosition.blockPosToChunkPositionAndOffset(c.blockPosition, chunkPos, blockOffset);

			if(!chunkSys.isPresent(chunkPos))
			{
				if(c.forceLoadChunk)
				{
					BasicChunk ch = createChunk(chunkPos, true);
					chunksTerrain[chunkPos] = ch;
					chunkStates[chunkPos] = ChunkState.active;
					setBlockCommands.insertBack(c);
				}
				else
					onSetFailure.emit(VoxelSetFailure(c.voxel, null, c.blockPosition));
				return false;
			}

			Optional!BasicChunk bc = chunkSys.borrow(chunkPos);
			if(bc == none) return false;
			scope(exit) chunkSys.give(*unwrap(bc));

			//setBlockOtherChunkOverruns(c.voxel, blockOffset.x, blockOffset.y, blockOffset.z, *bc.unwrap);

			bc.dispatch.chunk.set(blockOffset.x, blockOffset.y, blockOffset.z, c.voxel);
			bc.dispatch.chunk.needsMesh = true;

			return true;
		}

		const size_t l = setBlockCommands.length;
		foreach(i; 0 .. l)
		{
			bool succeed = executeSetVoxel(setBlockCommands.front);
			if(succeed)
				setBlockCommands.removeFront;
			else
			{
				VoxelSetCommand comm = setBlockCommands.front;
				setBlockCommands.removeFront;
				setBlockCommands.insert(comm);
			}
		}		
	}

	private void setBlockOtherChunkOverruns(Voxel voxel, int x, int y, int z, BasicChunk host) 
	in {
		assert(x >= 0 && x < ChunkData.chunkDimensions);
		assert(y >= 0 && y < ChunkData.chunkDimensions);
		assert(z >= 0 && z < ChunkData.chunkDimensions);
	}
	do {
		if(x == 0) {
			if(y == 0) {
				if(z == 0) {
					foreach(Vector3i off; chunkOffsets[0])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == ChunkData.chunkDimensions - 1) {
					foreach(Vector3i off; chunkOffsets[1])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(Vector3i off; chunkOffsets[2])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
			else if(y == ChunkData.chunkDimensions - 1) {
				if(z == 0) {
					foreach(Vector3i off; chunkOffsets[3])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == ChunkData.chunkDimensions - 1) {
					foreach(Vector3i off; chunkOffsets[4])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(Vector3i off; chunkOffsets[5])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
			else {
				if(z == 0) {
					foreach(Vector3i off; chunkOffsets[6])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == ChunkData.chunkDimensions - 1) {
					foreach(Vector3i off; chunkOffsets[7]) 
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(Vector3i off; chunkOffsets[8])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
		}
		else if(x == ChunkData.chunkDimensions - 1) {
			if(y == 0) {
				if(z == 0) {
					foreach(Vector3i off; chunkOffsets[9])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == ChunkData.chunkDimensions - 1) {
					foreach(Vector3i off; chunkOffsets[10])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(Vector3i off; chunkOffsets[11])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
			else if(y == ChunkData.chunkDimensions - 1) {
				if(z == 0) {
					foreach(Vector3i off; chunkOffsets[12])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == ChunkData.chunkDimensions - 1) {
					foreach(Vector3i off; chunkOffsets[13])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(Vector3i off; chunkOffsets[14])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
			else {
				if(z == 0) {
					foreach(Vector3i off; chunkOffsets[15])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == ChunkData.chunkDimensions - 1) {
					foreach(Vector3i off; chunkOffsets[16]) 
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(Vector3i off; chunkOffsets[17])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
		}

		if(y == 0) {
			if(z == 0) {
				foreach(Vector3i off; chunkOffsets[18])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
			else if(z == ChunkData.chunkDimensions - 1) {
				foreach(Vector3i off; chunkOffsets[19])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
			else {
				foreach(Vector3i off; chunkOffsets[20])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
		}
		else if(y == ChunkData.chunkDimensions - 1) {
			if(z == 0) {
				foreach(Vector3i off; chunkOffsets[21])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
			else if(z == ChunkData.chunkDimensions - 1) {
				foreach(Vector3i off; chunkOffsets[22])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
			else {
				foreach(Vector3i off; chunkOffsets[23])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
		}

		if(z == 0) {
			foreach(Vector3i off; chunkOffsets[24])
				setBlockForChunkOffset(off, host, x, y, z, voxel);
			return;
		}
		else if(z == ChunkData.chunkDimensions - 1) {
			foreach(Vector3i off; chunkOffsets[25])
				setBlockForChunkOffset(off, host, x, y, z, voxel);
			return;
		}
	}

	private void setBlockForChunkOffset(Vector3i off, BasicChunk host, int x, int y, int z, Voxel voxel) {
		ChunkPosition cp = ChunkPosition(host.position.x + off.x, host.position.y + off.y, host.position.z + off.z);

		int newX = x + (-off.x * ChunkData.chunkDimensions);
		int newY = y + (-off.y * ChunkData.chunkDimensions);
		int newZ = z + (-off.z * ChunkData.chunkDimensions);

		if(!chunkSys.isPresent(cp)) return;

		ChunkState* state = cp in chunkStates;
		if(*state == ChunkState.deallocated) return;

		Optional!BasicChunk bc;
		
		//mixin(ForceBorrowScope!("cp"));

		bc.dispatch.chunk.set(newX, newY, newZ, voxel);
		bc.dispatch.chunk.needsMesh = true;
	}+/
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

	/// handle all interactions
	void run()
	{
		executeSetVoxel;
		executeDeferredOverruns;
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
			bc.chunk.needsMesh = true;
			bc.chunk.dataLoadBlocking = false;

			distributeOverruns(*bc, order.offset, order.voxel);
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
		bc.chunk.needsMesh = true;
		bc.chunk.dataLoadBlocking = false;

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

class TerrainDataStream
{
	
}

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