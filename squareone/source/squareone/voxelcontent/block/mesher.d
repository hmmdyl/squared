module squareone.voxelcontent.block.mesher;

import squareone.voxel;
import squareone.voxelcontent.block.processor;
import squareone.voxelcontent.block.types;

import moxane.core;
import moxane.utils.maybe;

import dlib.math.vector;
import std.datetime.stopwatch;
import std.concurrency;
import std.container.dlist;
import std.algorithm.comparison : clamp;
import core.atomic;

package final class Mesher : IMesher
{
	/+private Object meshSyncObj;
	private DList!(MeshOrder) meshQueue;
	private Condition meshQueueWaiter;
	private Mutex meshQueueMutex;

	Object uploadSyncObj;
	DList!(BlockProcessor.MeshResult)* uploadQueue;

	BlockProcessor processor;
	Resources resources;
	MeshBufferHost host;

	bool busy;
	bool requiresRestart;

	double lowest, avg, highest;

	private Thread thread;

	this(Object uploadSyncObj, DList!(BlockProcessor.MeshResult)* uploadQueue, BlockProcessor processor, Resources resources, MeshBufferHost host)
	{
		meshSyncObj = new Object;
		meshQueueMutex = new Mutex;
		meshQueueWaiter = new Condition(meshQueueMutex);

		this.uploadSyncObj = uploadSyncObj;
		this.uploadQueue = uploadQueue;
		this.processor = processor;
		this.resources = resources;
		this.host = host;

		lowest = avg = highest = 0.0;

		thread = new Thread(&workerFuncRoot);
		thread.isDaemon = true;
		thread.name = BlockProcessor.stringof ~ " " ~ Mesher.stringof;
		thread.start;
	}

	void restart()
	{
		requiresRestart = false;
		thread.start;
	}

	private MeshOrder order;
	private IMeshableVoxelBuffer chunk;
	private MeshBuffer buffer;

	private void workerFuncRoot()
	{
		try workerFuncProper;
		catch(Throwable t)
		{
			import std.conv : to;
			Log log = processor.moxane.services.get!Log;
			log.write(Log.Severity.error, "Exception in thread " ~ thread.name ~ "\n\tMessage: " ~ to!string(t.message) ~ "\n\tLine: " ~ to!string(t.line) ~ "\n\tStacktrace: " ~ t.info.toString);
			log.write(Log.Severity.error, "Thread will be restarted...");

			if(chunk !is null)
			{
				chunk.meshBlocking(false, processor.id_);
				chunk.needsMesh = true;
			}
			chunk = null;

			if(buffer !is null)
			{
				buffer.reset;
				host.give(buffer);
			}
			buffer = null;

			order = MeshOrder();
			requiresRestart = true;
		}
	}

	private void workerFuncProper()
	{
		while(true)
		{
			busy = false;
			chunk = null;
			buffer = null;

			bool meshQueueEmpty = false;
			synchronized(meshSyncObj) meshQueueEmpty = meshQueue.empty;

			if(meshQueueEmpty)
				synchronized(meshQueueMutex)
					meshQueueWaiter.wait;
			synchronized(meshSyncObj)
			{
				order = meshQueue.front;
				chunk = order.chunk;
				meshQueue.removeFront;
			}

			if(chunk is null) continue;

			busy = true;
			do
				buffer = host.request(MeshSize.small);
			while(buffer is null);

			operateOnChunk;
		}
	}+/

	private IChannel!MeshOrder source_;
	@property IChannel!MeshOrder source() { return source_; }

	private float averageMeshTime_ = 0f;
	@property float averageMeshTime() { return averageMeshTime_; }

	private bool parked_ = true, terminated_ = false;
	@property bool parked() const { return parked_; }
	@property bool terminated() const { return terminated_; }

	private Tid thread;

	this(BlockProcessor processor, Resources resources, MeshBufferHost meshBufferHost, IChannel!MeshOrder source)
	in(processor !is null) in(resources !is null) in(meshBufferHost !is null) in(source !is null)
	{
		this.source_ = source;
		thread = spawn(&worker, cast(shared)processor, cast(shared)resources, cast(shared)meshBufferHost, cast(shared)source,
					   cast(shared)&parked_, cast(shared)&terminated_, cast(shared)&averageMeshTime_);
	}

	void kick() { send(thread, true); }
	void terminate() { send(thread, false); }
}

private void worker(shared BlockProcessor processor_, shared Resources resources_, shared MeshBufferHost host_, shared IChannel!MeshOrder source_,
					shared bool* parked, shared bool* terminated, shared float* averageMeshTime)
{
	BlockProcessor processor = cast(BlockProcessor)processor_;
	Resources resources = cast(Resources)resources_;
	MeshBufferHost host = cast(MeshBufferHost)host_;
	IChannel!MeshOrder source = cast(IChannel!MeshOrder)source_;

	Log log = processor.moxane.services.getAOrB!(VoxelLog, Log);

	auto uploadSyncObj = processor.uploadSyncObj;
	auto uploadQueue = &processor.uploadQueue;

	enum threadName = BlockProcessor.stringof ~ " " ~ Mesher.stringof;
	log.write(Log.Severity.info, threadName ~ " started");
	scope(failure) log.write(Log.Severity.panic, "Panic in " ~ threadName);
	scope(success) log.write(Log.Severity.info, threadName ~ " terminated");

	while(!*terminated)
	{
		receive(
				(bool m)
				{
					if(!m)
					{
						*terminated = true;
						return;
					}

					*parked = false;
					scope(exit) *parked = true;

					bool consuming = true;
					while(consuming)
					{
						Maybe!MeshOrder order = source.tryGet;
						if(order.isNull)
							consuming = false;
						else
						{
							MeshBuffer buffer;
							do buffer = host.request(MeshSize.small);
							while(buffer is null);

							operateOnChunk(*order.unwrap, buffer, resources, host, log, uploadSyncObj, uploadQueue, averageMeshTime);
						}
					}
				}
			);
	}
}

private void operateOnChunk(MeshOrder order, MeshBuffer buffer, Resources resources, MeshBufferHost host, Log log, Object uploadSyncObj, DList!(BlockProcessor.MeshResult)* uploadQueue, shared float* averageMeshTime_)
{
	IMeshableVoxelBuffer chunk = order.chunk;

	void addVert(Vector3f vert, Vector3f normal, uint meta)
	{
		if(buffer.ms == MeshSize.small) 
		{
			if(buffer.vertexCount + 1 >= vertsSmall) 
			{
				MeshBuffer nbmb;
				while(nbmb is null)
					nbmb = host.request(MeshSize.medium);
				buffer.chunkMax = chunk.dimensionsProper * chunk.voxelScale;

				copyBuffer(buffer, nbmb);

				host.give(buffer);
				buffer = nbmb;
			}
		}
		else if(buffer.ms == MeshSize.medium) 
		{
			if(buffer.vertexCount + 1 >= vertsMedium) 
			{
				MeshBuffer nbmb;
				while(nbmb is null)
					nbmb = host.request(MeshSize.full);
				buffer.chunkMax = chunk.dimensionsProper * chunk.voxelScale;

				copyBuffer(buffer, nbmb);

				host.give(buffer);
				buffer = nbmb;
			}
		}
		else 
		{
			if(buffer.vertexCount + 1 >= vertsFull) 
			{
				string exp = "Chunk (" ~ "" ~ ") is too complex to mesh. Error: too many vertices for buffer.";
				throw new Exception(exp);
			}
		}

		import std.conv : to;
		if(buffer.vertexCount + 1 == vertsSmall) { log.write(Log.Severity.panic, "Requires more than " ~ to!string(vertsSmall) ~ " vertices."); }

		buffer.add(vert, normal, meta);
	}

	Vector3f[64] verts, normals;
	ushort[64] textureIDs;

	immutable int blkskp = chunk.blockskip;
	immutable int chunkDimLod = chunk.dimensionsProper * chunk.blockskip;

	buffer.chunkMax = chunkDimLod * chunk.voxelScale;

	StopWatch sw = StopWatch(AutoStart.yes);

	for(int x = 0; x < chunkDimLod; x += blkskp) 
	{
		for(int y = 0; y < chunkDimLod; y += blkskp)  
		{
			for(int z = 0; z < chunkDimLod; z += blkskp)  
			{
				Voxel v = chunk.get(x, y, z);

				IBlockVoxelMesh bvm = cast(IBlockVoxelMesh)resources.getMesh(v.mesh);
				if(bvm is null) continue;

				Voxel[6] neighbours;
				SideSolidTable[6] isSidesSolid;

				neighbours[VoxelSide.nx] = chunk.get(x - blkskp, y, z);
				neighbours[VoxelSide.px] = chunk.get(x + blkskp, y, z);
				neighbours[VoxelSide.ny] = chunk.get(x, y - blkskp, z);
				neighbours[VoxelSide.py] = chunk.get(x, y + blkskp, z);
				neighbours[VoxelSide.nz] = chunk.get(x, y, z - blkskp);
				neighbours[VoxelSide.pz] = chunk.get(x, y, z + blkskp);

				isSidesSolid[VoxelSide.nx] = resources.getMesh(neighbours[VoxelSide.nx].mesh).isSideSolid(neighbours[VoxelSide.nx], VoxelSide.px);
				isSidesSolid[VoxelSide.px] = resources.getMesh(neighbours[VoxelSide.px].mesh).isSideSolid(neighbours[VoxelSide.px], VoxelSide.nx);
				isSidesSolid[VoxelSide.ny] = resources.getMesh(neighbours[VoxelSide.ny].mesh).isSideSolid(neighbours[VoxelSide.ny], VoxelSide.py);
				isSidesSolid[VoxelSide.py] = resources.getMesh(neighbours[VoxelSide.py].mesh).isSideSolid(neighbours[VoxelSide.py], VoxelSide.ny);
				isSidesSolid[VoxelSide.nz] = resources.getMesh(neighbours[VoxelSide.nz].mesh).isSideSolid(neighbours[VoxelSide.nz], VoxelSide.pz);
				isSidesSolid[VoxelSide.pz] = resources.getMesh(neighbours[VoxelSide.pz].mesh).isSideSolid(neighbours[VoxelSide.pz], VoxelSide.nz);

				int vertCount;
				bvm.generateMesh(v, chunk.blockskip, neighbours, isSidesSolid, Vector3i(x, y, z), verts, normals, vertCount);

				IBlockVoxelMaterial bvMat = cast(IBlockVoxelMaterial)resources.getMaterial(v.material);
				if(bvMat is null) continue;
				bvMat.generateTextureIDs(vertCount, verts, normals, textureIDs);

				foreach(int i; 0 .. vertCount)
					addVert(verts[i] * ChunkData.voxelScale, normals[i], textureIDs[i] & 2047);
			}
		}
	}

	if(buffer.vertexCount == 0)
	{
		buffer.reset;
		host.give(buffer);
		buffer = null;

		BlockProcessor.MeshResult mr;
		mr.order = order;
		mr.buffer = null;
		synchronized(uploadSyncObj)
			uploadQueue.insert(mr);
	}
	else
	{
		BlockProcessor.MeshResult mr;
		mr.order = order;
		mr.buffer = buffer;
		synchronized(uploadSyncObj)
			uploadQueue.insert(mr);
	}

	sw.stop;
	if(atomicLoad(*averageMeshTime_) == 0f) atomicStore(*averageMeshTime_, sw.peek.total!"nsecs" * (1f / 1_000_000f));
	else
	{
		atomicOp!"+="(*averageMeshTime_, sw.peek.total!"nsecs" * (1f / 1_000_000f));
		atomicOp!"*="(*averageMeshTime_, 0.5f);
	}
}

enum MeshSize {
	small,
	medium,
	full
}

enum int vertsSmall = 80_192;
enum int vertsSmallMemoryPerArr = vertsSmall * Vector3f.sizeof;

enum int vertsMedium = 24_576;
enum int vertsMediumMemoryPerArr = vertsMedium * Vector3f.sizeof;

enum int vertsFull = 147_456;
enum int vertsFullMemoryPerArr = vertsFull * Vector3f.sizeof;

private void copyBuffer(MeshBuffer smaller, MeshBuffer bigger) 
in {
	if(smaller.ms == MeshSize.small)
		assert(bigger.ms == MeshSize.medium || bigger.ms == MeshSize.full);
	if(smaller.ms == MeshSize.medium)
		assert(bigger.ms == MeshSize.full);
	assert(smaller.ms != MeshSize.full);
}
do {
	foreach(int v; 0 .. smaller.vertexCount)
		bigger.add(smaller.vertices[v], smaller.normals[v], smaller.meta[v]);
}

class MeshBuffer
{
	Vector3f[] vertices;
	Vector3f[] normals;
	uint[] meta;

	uint[] compressedVertices;
	uint[] compressedNormals;

	int vertexCount;

	const MeshSize ms;

	enum tenBitMax = 2 ^^ 10 - 1;
	private float chunkMax_ = 0f;
	@property float chunkMax() const { return chunkMax_; }
	@property void chunkMax(float cm)
	{
		chunkMax_ = cm;
		inv = 1f / cm;
		fit10Bit = tenBitMax * inv;
	}
	float inv = 0f, fit10Bit = 0f;

	this(MeshSize ms) 
	{
		this.ms = ms;

		if(ms == MeshSize.small) 
		{
			vertices.length = vertsSmall;
			normals.length = vertsSmall;
			meta.length = vertsSmall;
			compressedVertices.length = vertsSmall;
			compressedNormals.length = vertsSmall;
		}
		if(ms == MeshSize.medium) 
		{
			vertices.length = vertsMedium;
			normals.length = vertsMedium;
			meta.length = vertsMedium;
			compressedVertices.length = vertsMedium;
			compressedNormals.length = vertsMedium;
		}
		if(ms == MeshSize.full) 
		{
			vertices.length = vertsFull;
			normals.length = vertsFull;
			meta.length = vertsFull;
			compressedVertices.length = vertsFull;
			compressedNormals.length = vertsFull;
		}
	}

	void add(Vector3f vert, Vector3f normal, uint meta) 
	{
		vertices[vertexCount] = vert;
		normals[vertexCount] = normal;
		this.meta[vertexCount] = meta;

		const float vx = clamp(vert.x, 0f, chunkMax_) * fit10Bit;
		uint vxU = cast(uint)vx & tenBitMax;

		const float vy = clamp(vert.y, 0f, chunkMax_) * fit10Bit;
		uint vyU = cast(uint)vy & tenBitMax;
		vyU <<= 10;

		const float vz = clamp(vert.z, 0f, chunkMax_) * fit10Bit;
		uint vzU = cast(uint)vz & tenBitMax;
		vzU <<= 20;

		compressedVertices[vertexCount] = vxU | vyU | vzU;

		const float nx = (((clamp(normal.x, -1f, 1f) + 1f) * 0.5f) * tenBitMax);
		const float ny = (((clamp(normal.y, -1f, 1f) + 1f) * 0.5f) * tenBitMax);
		const float nz = (((clamp(normal.z, -1f, 1f) + 1f) * 0.5f) * tenBitMax);

		const uint nxU = (cast(uint)nx & tenBitMax);
		const uint nyU = (cast(uint)ny & tenBitMax) << 10;
		const uint nzU = (cast(uint)nz & tenBitMax) << 20;

		compressedNormals[vertexCount] = nxU | nyU | nzU;

		vertexCount++;
	}

	void reset() 
	{ vertexCount = 0; }
}

package class MeshBufferHost
{
	enum int smallMeshCount = 20;
	enum int mediumMeshCount = 0;
	enum int fullMeshCount = 0;

	private DList!(MeshBuffer) smallMeshes;
	private DList!(MeshBuffer) mediumMeshes;
	private DList!(MeshBuffer) fullMeshes;

	this() 
	{
		foreach(int x; 0 .. smallMeshCount) 
			smallMeshes.insertBack(new MeshBuffer(MeshSize.small));
		foreach(int x; 0 .. mediumMeshCount)
			mediumMeshes.insertBack(new MeshBuffer(MeshSize.medium));
		foreach(int x; 0 .. fullMeshCount)
			fullMeshes.insertBack(new MeshBuffer(MeshSize.full));
	}

	MeshBuffer request(MeshSize m) 
	{
		synchronized(this) 
		{
			if(m == MeshSize.small) 
			{
				if(!smallMeshes.empty) 
				{
					auto bmb = smallMeshes.back;
					smallMeshes.removeBack();
					return bmb;
				}
			}
			if(m == MeshSize.medium) 
			{
				if(!mediumMeshes.empty) 
				{
					auto bmb = mediumMeshes.back;
					mediumMeshes.removeBack();
					return bmb;
				}
			}
			if(m == MeshSize.full) 
			{
				if(!fullMeshes.empty) 
				{
					auto bmb = fullMeshes.back;
					fullMeshes.removeBack();
					return bmb;
				}
			}

			return null;
		}
	}

	void give(MeshBuffer bmb) 
	{
		synchronized(this) 
		{
			bmb.reset();

			if(bmb.ms == MeshSize.small)
				smallMeshes.insertBack(bmb);
			if(bmb.ms == MeshSize.medium) 
				mediumMeshes.insertBack(bmb);
			if(bmb.ms == MeshSize.full) 
				fullMeshes.insertBack(bmb);
		}
	}
}