module squareone.common.terrain.generation.root;

import moxane.core;
import squareone.common.terrain.position;
import squareone.common.voxel;
import core.thread;

@safe:

struct NoiseGeneratorOrder
{
	ILoadableVoxelBuffer chunk;
	ChunkPosition chunkPosition;
	Fiber fiber;

	bool loadRing, loadChunk;

	this(ILoadableVoxelBuffer chunk, ChunkPosition position, Fiber fiber, bool loadChunk, bool loadRing)
	{
		this.chunk = chunk;
		this.chunkPosition = position;
		this.fiber = fiber;
		this.loadChunk = loadChunk;
		this.loadRing = loadRing;
	}
}

class NoiseGeneratorManager2(CommandType)
{
	alias createThreadDel = NoiseGenerator2!CommandType delegate(NoiseGeneratorManager2!CommandType, VoxelRegistry, IChannel!CommandType) @trusted;
	private createThreadDel createThread_;
	@property createThreadDel createThread() { return createThread_; }

	VoxelRegistry resources;
	Log log;

	enum initialNumWorkers = 2;

	private Channel!CommandType work;
	private NoiseGenerator2!CommandType[] workers;

	this(VoxelRegistry resources, Log log, createThreadDel createThread)
	in(resources !is null) in(createThread !is null)
	{
		this.resources = resources;
		this.log = log;
		this.createThread_ = createThread;
		work = new Channel!CommandType;
		workers = new NoiseGenerator2!CommandType[](0);

		foreach(x; 0 .. initialNumWorkers)
			workers ~= createThread_(this, resources, work);
	}

	~this()
	{
		foreach(worker; workers)
			worker.terminate;
	}

	void managerTick(float timestep) 
	{
		manageWorkers;

		/+if(work.length > 100)
		{
		if(log !is null) log.write(Log.Severity.info, "Created new noise generator worker");
		workers ~= createThread_(this, resources, work);
		}
		if(work.length < 25 && workers.length > initialNumWorkers)
		{
		if(log !is null) log.write(Log.Severity.info, "Deleted noise generator worker");
		workers[workers.length - 1].terminate;
		}+/
	}

	void generateChunk(CommandType order)
	{
		order.chunk.dataLoadBlocking = true;
		order.chunk.needsData = false;
		work.send(order);
	}

	private void manageWorkers()
	{
		foreach(ref NoiseGenerator2!CommandType worker; workers)
		{
			if(worker.parked && !worker.terminated)
				worker.kick;
			if(worker.terminated)
				workers = workers[0..$-1];
		}
	}
}

abstract class NoiseGenerator2(CommandType) : IWorkerThread!CommandType
{
	NoiseGeneratorManager2!CommandType manager;
	VoxelRegistry resources;

	this(NoiseGeneratorManager2!CommandType manager, VoxelRegistry resources)
	in(manager !is null) in(resources !is null)
	{
		this.manager = manager;
		this.resources = resources;
	}
}