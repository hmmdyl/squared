module squareone.terrain.basic.manager;

import squareone.terrain.basic.chunk;
import squareone.terrain.gen.noisegen;
import squareone.voxel;
import moxane.core;
import moxane.graphics.renderer;

import dlib.math;
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
		foreach(proc; 0 .. btm.resources.processorCount)
		{
			IProcessor p = btm.resources.getProcessor(proc);
			p.prepareRender(renderer);
			scope(exit) p.endRender;

			foreach(ref BasicChunk chunk; btm.chunksTerrain)
				p.render(chunk.chunk, lc, drawCalls, numVerts);
		}
	}
}

struct BasicTMSettings
{
	Vector3i addRange, extendedAddRange, removeRange;
	Resources resources;
}

final class BasicTerrainManager
{
	enum ChunkState
	{
		deallocated,
		/// memory is assigned, but no voxel data.
		notLoaded,
		active
	}

	Resources resources;
	Moxane moxane;

	private BasicChunk[ChunkPosition] chunksTerrain;
	private ChunkState[ChunkPosition] chunkStates;

	@property size_t numChunks() const { return chunksTerrain.length; }

	const BasicTMSettings settings;

	Vector3f cameraPosition;
	NoiseGeneratorManager noiseGeneratorManager;

	this(Moxane moxane, BasicTMSettings settings)
	{
		this.moxane = moxane;
		this.settings = settings;
		resources = settings.resources;

		chunkSys = new ChunkInteraction(this);
		voxel = new VoxelInteraction(this);

		noiseGeneratorManager = new NoiseGeneratorManager(resources, 1, () => new DefaultNoiseGenerator(moxane), 0);
		auto ecpcNum = (settings.extendedAddRange.x * 2 + 1) * (settings.extendedAddRange.y * 2 + 1) * (settings.extendedAddRange.z * 2 + 1);
		extensionCPCache = new ChunkPosition[ecpcNum];
	}

	~this()
	{
		destroy(noiseGeneratorManager);
	}

	void update()
	{
		const ChunkPosition cp = ChunkPosition.fromVec3f(cameraPosition);

		addChunksLocal(cp);
		addChunksExtension(cp);
		executeSetVoxels;
		noiseGeneratorManager.pumpCompletedQueue;
		foreach(ref BasicChunk bc; chunksTerrain)
		{
			manageChunkState(bc);
			removeChunkHandler(bc, cp);
		}
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

		for(int x = lower.x; x < upper.x; x++)
		{
			for(int y = lower.y; y < upper.y; y++)
			{
				for(int z = lower.z; z < upper.z; z++)
				{
					auto newCp = ChunkPosition(x, y, z);

					ChunkState* getter = newCp in chunkStates;
					bool doAdd = getter is null || *getter == ChunkState.deallocated;

					if(doAdd)
					{
						auto chunk = createChunk(newCp);
						chunksTerrain[newCp] = chunk;
						chunkStates[newCp] = ChunkState.notLoaded;
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
			   chunk.chunk.needsMesh || chunk.chunk.isAnyMeshBlocking)
				chunk.chunk.pendingRemove = true;
			else
			{
				foreach(int proc; 0 .. resources.processorCount)
					resources.getProcessor(proc).removeChunk(chunk.chunk);

				chunksTerrain.remove(chunk.position);
				chunkStates.remove(chunk.position);
				chunk.chunk.deinitialise();
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
		enum addMax = 80;

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
			}

			if(chunk.needsMesh && !chunk.needsData && !chunk.dataLoadBlocking && !chunk.dataLoadCompleted && chunk.readonlyRefs == 0)
			{
				if(chunk.airCount == ChunkData.chunkOverrunDimensionsCubed || 
				   chunk.solidCount == ChunkData.chunkOverrunDimensionsCubed) 
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

	struct ChunkInteraction
	{
		private BasicTerrainManager m;
		invariant { assert(m !is null); }

		@property bool isPresent(ChunkPosition pos) const
		{
			const ChunkState* state = pos in m.chunkStates;
			if(state is null || *state == ChunkState.deallocated || *state == ChunkState.notLoaded)
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

	private bool isChunkInBounds(ChunkPosition camera, ChunkPosition position)
	{
		return position.x >= camera.x - settings.removeRange.x && position.x < camera.x + settings.removeRange.x &&
			position.y >= camera.y - settings.removeRange.y && position.y < camera.y + settings.removeRange.y &&
			position.z >= camera.z - settings.removeRange.z && position.z < camera.z + settings.removeRange.z;
	}

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
			if(state is null || *state != ChunkState.active)
				return no!Voxel;

			return Optional!Voxel(manager.chunksTerrain[chunkPosition].chunk.get(cp.x, cp.y, cp.z));
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
		void executeSetVoxel(VoxelSetCommand c)
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
				return;
			}

			Optional!BasicChunk bc;
			mixin(ForceBorrowScope!("chunkPos"));

			setBlockOtherChunkOverruns(c.voxel, blockOffset.x, blockOffset.y, blockOffset.z, *bc.unwrap);

			bc.dispatch.chunk.set(blockOffset.x, blockOffset.y, blockOffset.z, c.voxel);
			bc.dispatch.chunk.needsMesh = true;
		}

		const size_t l = setBlockCommands.length;
		foreach(i; 0 .. l)
		{
			executeSetVoxel(setBlockCommands.front);
			setBlockCommands.removeFront;
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

		Optional!BasicChunk bc;
		mixin(ForceBorrowScope!("cp"));

		bc.dispatch.chunk.set(newX, newY, newZ, voxel);
		bc.dispatch.chunk.needsMesh = true;
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