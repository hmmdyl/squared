module squareone.client.terrain.basic.engine;

import squareone.client.terrain.basic.chunk;
import squareone.common.terrain.basic.interaction;
import squareone.common.terrain.basic.packets;
import squareone.common.terrain.position;
import squareone.common.terrain.generation.v1;
import squareone.common.voxel;

import moxane.core;
import moxane.utils.maybe;

import dlib.math;

import containers;

import std.datetime.stopwatch;

@safe:

struct TerrainSettings
{
	Vector3i addRange;
	Vector3i extendedAddRange;
	Vector3i removeRange;
	Vector3i playerLocalRange;
	VoxelRegistry registry;
	Moxane moxane;
}

enum ChunkState
{
	deallocated,
	notLoaded,
	hibernated,
	active
}

struct Diagnostics
{
	size_t created;
	size_t hibernated;
	size_t removed;
	size_t compressed;
	size_t decompressed;
	size_t noiseIssued;
	size_t noiseCompleted;
	size_t meshesOrdered;
}

struct Camera
{
	Vector3f position;
	ChunkPosition asChunk;
	ChunkPosition asChunkPrevious;

	private void init(Vector3f cameraPos)
	{
		position = cameraPos;
		asChunk = ChunkPosition.fromVec3f(cameraPos);
		asChunkPrevious = asChunk - (ChunkPosition(1, 1, 1));
	}
}

private struct Meshing
{
	private Channel!MeshOrder[IProcessor] queues;
	private IMesher[][IProcessor] meshers;
	private bool shouldKick;

	void initialise(VoxelRegistry registry)
	{
		foreach(pid; 0 .. registry.processorCount)
		{
			IProcessor processor = registry.getProcessor(pid);
			queues[processor] = new Channel!MeshOrder;
			meshers[processor] = new IMesher[](processor.minMeshers);
			foreach(mid; 0 .. processor.minMeshers)
				meshers[processor][mid] = processor.requestMesher(queues[processor]);
		}
	}
}

private struct Generation
{
	NoiseGeneratorManager2!NoiseGeneratorOrder manager;

	void initialise(Moxane moxane, VoxelRegistry registry) @trusted
	{
		import std.functional : toDelegate;
		manager = new NoiseGeneratorManager2!NoiseGeneratorOrder(
			registry, moxane.services.getAOrB!(VoxelLog, Log),
			toDelegate((NoiseGeneratorManager2!NoiseGeneratorOrder m, VoxelRegistry r, IChannel!NoiseGeneratorOrder o) => new DefaultNoiseGeneratorV1(m, r, o)));
	}
}

private struct Extension
{
	private StopWatch sortTimer;
	private bool isSorted;
	private ChunkPosition[] cache;
	private size_t bias, length;

	void initialise(Vector3i extensionRange)
	{
		auto ecpcNum = (extensionRange.x * 2 + 1) * 
			(extensionRange.y * 2 + 1) * 
			(extensionRange.z * 2 + 1);
		cache = new ChunkPosition[ecpcNum];
		sortTimer.start;
	}
}

final class TerrainEngine 
{
	package Chunk[ChunkPosition] chunks;
	private ChunkState[ChunkPosition] states;
	@property size_t numChunks() const { return chunks.length; }

	TerrainSettings settings;
	@property VoxelRegistry resources() { return settings.registry; }

	private Diagnostics diagnostics_;
	@property Diagnostics diagnostics() const { return diagnostics_; }

	Camera camera;

	VoxelInteraction voxelInteraction;
	ChunkInteraction chunkInteraction;

	private Meshing meshing;
	private Generation generation;
	private Extension extension;

	this(TerrainSettings settings, Vector3f cameraPosition)
	{
		this.settings = settings;
		camera.init(cameraPosition);

		meshing.initialise(resources);
		generation.initialise(settings.moxane, resources);
		extension.initialise(settings.extendedAddRange);
		voxelInteraction = new VoxelInteraction(this);
		chunkInteraction = new ChunkInteraction(this);
	}

	void update()
	{
		generation.manager.managerTick(settings.moxane.deltaTime);
		manageChunks;
	}

	private void manageChunks()
	{
		meshing.shouldKick = false;

		immutable ChunkPosition cp = ChunkPosition.fromVec3f(camera.position);
		camera.asChunkPrevious = camera.asChunk;
		camera.asChunk = cp;

		kickMeshers;
		scope(success) kickMeshers;

		addChunksFromExtension;
		voxelInteraction.run;

		foreach(Chunk chunk; chunks) manageChunkState(chunk);
		foreach(Chunk chunk; chunks) removeChunkHandler(chunk);
	}

	private Chunk createChunk(ChunkPosition pos, bool needsData = true)
	{
		auto c = new Chunk(resources);
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
		if(camera.asChunk == camera.asChunkPrevious)
			return;

		Vector3i lower = Vector3i(cp.x - settings.addRange.x,
								  cp.y - settings.addRange.y,
								  cp.z - settings.addRange.z);

		Vector3i upper = Vector3i(cp.x + settings.addRange.x,
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

					ChunkState* getter = newCp in states;
					bool absent = getter is null || *getter == ChunkState.deallocated;
					bool doAdd = absent || (isInPlayerLocalBounds(cp, newCp) && *getter == ChunkState.hibernated);

					if(doAdd)
					{
						auto chunk = createChunk(newCp);
						chunks[newCp] = chunk;
						states[newCp] = ChunkState.notLoaded;
						diagnostics_.created++;
					}
				}
			}
		}
	}

	private void removeChunkHandler(Chunk chunk) @trusted
	{
		if(!isChunkInBounds(camera.asChunk, chunk.position))
		{
			if(chunk.needsData || chunk.dataLoadBlocking || chunk.dataLoadCompleted ||
			   chunk.needsMesh || chunk.isAnyMeshBlocking || chunk.readonlyRefs > 0)
				chunk.pendingRemove = true;
			else
			{
				foreach(int proc; 0 .. resources.processorCount)
					resources.getProcessor(proc).removeChunk(chunk);

				chunks.remove(chunk.position);
				states.remove(chunk.position);
				chunk.deinitialise();

				//destroy(chunk);

				diagnostics_.removed++;
			}
		}
	}

	private void addChunksFromExtension()
	{
		bool doSort;

		if(!extension.sortTimer.running)
		{
			extension.sortTimer.start;
			doSort = true;
		}
		if(extension.sortTimer.peek.total!"msecs"() >= 300 && camera.asChunk != camera.asChunkPrevious)
		{
			extension.sortTimer.reset;
			extension.sortTimer.start;
			doSort = true;
		}

		if(doSort)
		{
			extension.isSorted = false;

			import std.parallelism;

			void sortTask(ChunkPosition[] cache)
			{
				import std.algorithm.sorting : sort;

				ChunkPosition lc = camera.asChunk;
				immutable camf = camera.position.lengthsqr;

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
							extension.cache[c++] = ChunkPosition(x, y, z);
				extension.length = c;
				extension.bias = 0;

				sort!cdCmp(cache[0..extension.length]);

				extension.isSorted = true;
			}

			taskPool.put(task(&sortTask, extension.cache));
		}

		if(!extension.isSorted) return;

		int doAddNum;
		enum addMax = 10;

		foreach(ChunkPosition pos; extension.cache[extension.bias .. extension.length])
		{
			ChunkState* getter = pos in states;
			bool absent = getter is null || *getter == ChunkState.deallocated;
			bool doAdd = absent || (isInPlayerLocalBounds(camera.asChunk, pos) && *getter == ChunkState.hibernated);

			if(doAdd)
			{
				if(doAddNum > addMax) return;

				Chunk chunk = createChunk(pos);
				chunks[pos] = chunk;
				states[pos] = ChunkState.notLoaded;

				doAddNum++;

				diagnostics_.created++;
				extension.bias++;
			}
		}
	}

	private void manageChunkState(Chunk chunk)
	{
		if(chunk.needsData && !chunk.isAnyMeshBlocking && chunk.readonlyRefs == 0) 
		{
			chunkLoadNeighbours(chunk);
		}
		if(chunk.dataLoadCompleted)
		{
			states[chunk.position] = ChunkState.active;
			chunk.needsMesh = true;
			chunk.dataLoadCompleted = false;
			chunk.hasData = true;

			diagnostics_.noiseCompleted++;
		}

		if(chunk.needsMesh && !chunk.needsData && !chunk.dataLoadBlocking && !chunk.dataLoadCompleted && chunk.readonlyRefs == 0)
		{
			if((chunk.airCount == ChunkData.chunkOverrunDimensionsCubed || 
				chunk.solidCount == ChunkData.chunkOverrunDimensionsCubed ||
				chunk.fluidCount == ChunkData.chunkOverrunDimensionsCubed) && !isInPlayerLocalBounds(camera.asChunk, chunk.position)) 
			{
				chunks.remove(chunk.position);
				chunk.deinitialise();
				states[chunk.position] = ChunkState.hibernated;
				diagnostics_.hibernated++;

				//delete chunk;

				return;
			}
			else
			{
				if(chunk.isCompressed)
				{
					decompressChunk(chunk);
					diagnostics_.decompressed++;
				}
				meshChunks(MeshOrder(chunk, true, true, false));
				if(!meshing.shouldKick)
				{
					meshing.shouldKick = true;
					kickMeshers;
				}

				diagnostics_.meshesOrdered++;
			}
			chunk.needsMesh = false;
		}

		if(isInPlayerLocalBounds(camera.asChunk, chunk.position) && chunk.isCompressed)
		{
			decompressChunk(chunk);
			diagnostics_.decompressed++;
		}

		if(!chunk.needsMesh && !chunk.needsData && !chunk.dataLoadBlocking && !chunk.dataLoadCompleted 
		   && chunk.readonlyRefs == 0 && !chunk.isAnyMeshBlocking && 
		   !isInPlayerLocalBounds(camera.asChunk, chunk.position) && !chunk.isCompressed)
		{
			compressChunk(chunk);
			diagnostics_.compressed++;
		}
	}

	private void kickMeshers()
	{
		foreach(IProcessor processor, IMesher[] meshersForProcessor; meshing.meshers)
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
		foreach(IProcessor processor, IMesher[] meshersForProcessor; meshing.meshers)
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
		foreach(processor, channel; meshing.queues)
		{
			order.chunk.meshBlocking(true, processor.id);
			channel.send(order);
		}
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

	private void chunkLoadNeighbours(Chunk bc)
	{
		enum CSource
		{
			activeChunk,
			region,
			noise
		}

		NoiseGeneratorOrder noiseOrder = NoiseGeneratorOrder(bc, bc.position, null, true, true);
		generation.manager.generateChunk(noiseOrder);
	}
}

final class VoxelInteraction : IVoxelInteraction
{
	TerrainEngine engine;
	this(TerrainEngine engine) in(engine !is null) { this.engine = engine; }

	Maybe!Voxel get(BlockPosition position) 
	{  
		ChunkPosition cp;
		BlockOffset off;
		ChunkPosition.blockPosToChunkPositionAndOffset(position, cp, off);

		return get(cp, off);
	}

	Maybe!Voxel get(ChunkPosition chunkPosition, BlockOffset offset) 
	{ 
		ChunkState* state = chunkPosition in engine.states;
		if(state is null) 
			return Maybe!Voxel();
		if(*state == ChunkState.deallocated || *state == ChunkState.notLoaded) 
			return Maybe!Voxel();

		Chunk* bc = chunkPosition in engine.chunks;
		if(bc is null)
			return Maybe!Voxel();
		if(!bc.hasData) 
			return Maybe!Voxel();

		// does not collide with readonly refs, meshers
		if(bc.needsData || bc.dataLoadBlocking || 
		   bc.dataLoadCompleted || bc.isCompressed)
			return Maybe!Voxel();

		return Maybe!Voxel(bc.get(offset.x, offset.y, offset.z));
	}

	void set(Voxel voxel, BlockPosition position) {}
	void set(Voxel voxel, ChunkPosition chunkPosition, BlockOffset offset) {}

	private struct VoxelSetOrder
	{
		ChunkPosition chunkPosition;
		BlockOffset offset;
		Voxel voxel;
		this(ChunkPosition chunkPosition, BlockOffset offset, Voxel voxel) { this.chunkPosition = chunkPosition; this.offset = offset; this.voxel = voxel; }
	}

	private CyclicBuffer!VoxelSetOrder voxelSetCommands;
	private CyclicBuffer!VoxelSetOrder overrunSetCommands; // if chunk is busy, add to queue and run after

	private CyclicBuffer!Chunk chunksToMesh;

	/// handle all interactions
	void run()
	{
		executeSetVoxel;
		executeDeferredOverruns;

		auto length = chunksToMesh.length;
		foreach(size_t chunkID; 0 .. length)
		{
			Chunk bc = chunksToMesh.front;
			chunksToMesh.popFront;

			bc.needsMesh = true;
		}
	}

	/// handle direct voxel sets
	private void executeSetVoxel() @trusted
	{
		size_t length = voxelSetCommands.length;
		foreach(size_t commID; 0 .. length)
		{
			VoxelSetOrder order = voxelSetCommands.front;
			voxelSetCommands.popFront;

			// continue = discard

			ChunkState* state = order.chunkPosition in engine.states;
			if(state is null) 
				continue; // discard
			if(*state == ChunkState.notLoaded || *state == ChunkState.deallocated) 
				continue;

			Chunk* bc = order.chunkPosition in engine.chunks;
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
	private void distributeOverruns(Chunk host, BlockOffset blockPos, Voxel voxel)
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
	private void setOverrunChunk(Chunk bc, BlockOffset offset, BlockOffset blockPosLocal, Voxel voxel)
	{
		ChunkPosition newCP = ChunkPosition(bc.position.x + offset.x, bc.position.y + offset.y, bc.position.z + offset.z);
		BlockOffset newP = blockPosLocal + (-offset * ChunkData.chunkDimensions);
		handleChunkOverrun(newCP, newP, voxel);
	}

	/// if chunk is available, set its overrun, otherwise this will defer the command to next frame.
	private bool handleChunkOverrun(ChunkPosition cp, BlockOffset pos, Voxel voxel) @trusted
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

		ChunkState* state = cp in engine.states;
		if(state is null)
			return false;
		if(*state == ChunkState.notLoaded || *state == ChunkState.deallocated)
			return false;

		Chunk* bc = cp in engine.chunks;
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

final class ChunkInteraction : IChunkInteraction!(Chunk, ReadonlyChunk)
{
	TerrainEngine engine;
	this(TerrainEngine engine) in(engine !is null) { this.engine = engine; }

	Chunk borrow(ChunkPosition chunkPosition) 
	{ 
		ChunkState* state = chunkPosition in engine.states;
		if(state is null)
			return null;
		if(*state == ChunkState.notLoaded || *state == ChunkState.deallocated)
			return null;

		Chunk* bc = chunkPosition in engine.chunks;
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

	Maybe!ReadonlyChunk borrowReadonly(ChunkPosition cp) 
	{ 
		ChunkState* state = cp in engine.states;
		if(state is null)
			return Maybe!ReadonlyChunk();
		if(*state == ChunkState.notLoaded || *state == ChunkState.deallocated)
			return Maybe!ReadonlyChunk();

		Chunk* bc = cp in engine.chunks;
		if(bc is null)
			return Maybe!ReadonlyChunk();
		if(bc.needsData || bc.dataLoadBlocking || 
		   bc.dataLoadCompleted || bc.isCompressed)
			return Maybe!ReadonlyChunk();

		ReadonlyChunk ro = ReadonlyChunk(*bc);
		bc.incrementReadonlyRef;

		return Maybe!ReadonlyChunk(ro);
	}

	void give(Chunk bc) 
	{
		if(bc.dataLoadBlocking)
		{
			bc.dataLoadBlocking = false;
			bc.dataLoadCompleted = true;
		}
	}

	void give(ReadonlyChunk rc) { rc.chunk.decrementReadonlyRef; }
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

template ForceBorrowScope(string chunkPosName, string basicChunkName = "bc", bool outer = false, string man = "manager")
{
	const char[] ForceBorrowScope = "do " ~ basicChunkName ~ " = " ~ (outer == true ? man : "this") ~ ".chunkSys.borrow(" ~ chunkPosName ~ "); while(" ~ basicChunkName ~ ".unwrap is null); scope(exit) " ~ (outer == true ? man : "this") ~ ".chunkSys.give(*" ~ basicChunkName ~ ".unwrap); ";
}

template ForceBorrowReadonly(string chunkPosName, string basicChunkName = "bc", bool outer = false, string man = "manager")
{
	const char[] ForceBorrowReadonly = "do " ~ basicChunkName ~ " = " ~ (outer == true ? man : "this") ~ ".chunkSys.borrowReadonly(" ~ chunkPosName ~ "); while(" ~ basicChunkName ~ ".unwrap is null); ";
}