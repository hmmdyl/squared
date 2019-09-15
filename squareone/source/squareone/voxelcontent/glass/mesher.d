module squareone.voxelcontent.glass.mesher;

import squareone.voxelcontent.glass.processor;
import squareone.voxelcontent.glass.types;
import squareone.voxel;

import moxane.core;
import moxane.utils.pool;
import moxane.utils.maybe;
import std.container.dlist;

import dlib.math.vector;
import dlib.math.utils;

import core.thread : Thread;
/+import core.sync.condition : Condition;
import core.sync.mutex : Mutex;+/

package class GlassMesher
{
	GlassProcessor processor;

	Channel!MeshOrder orders;

	Pool!(CompressedMeshBuffer)* meshBufferPool;
	Channel!MeshResult results;

	private Thread thread;
	private bool terminate;

	this(GlassProcessor processor, Pool!(CompressedMeshBuffer)* pool, Channel!MeshResult results)
	in(processor !is null)
	do {
		this.processor = processor;
		this.meshBufferPool = pool;
		this.results = results;

		orders = new Channel!MeshOrder;

		thread = new Thread(&worker);
		thread.name = GlassProcessor.stringof ~ " " ~ GlassMesher.stringof;
		thread.isDaemon = true;
		thread.start;
	}

	private bool disposed;
	~this()
	{
		if(!disposed) dispose();
	}

	void dispose()
	{
		scope(exit) disposed = true;

		if(thread !is null)
		{
			if(thread.isRunning)
			{
				terminate = true;
				orders.notifyUnsafe;
				thread.join;
			}
		}
	}

	private void worker()
	{
		try
		{
			while(!terminate)
			{
				Maybe!MeshOrder order = orders.await;
				if(MeshOrder* o = order.unwrap)
					execute(*o);
				else return;
			}
		}
		catch(Throwable t)
		{
			import std.conv : to;
			Log log = processor.moxane.services.getAOrB!(VoxelLog, Log);
			log.write(Log.Severity.error, "Exception in " ~ thread.name ~ "\n\tMessage: " ~ to!string(t.message) ~ "\n\tLine: " ~ to!string(t.line) ~ "\n\tStacktrace: " ~ t.info.toString);
			log.write(Log.Severity.error, "Thread will not be restarted.");
		}
	}

	private void execute(MeshOrder o)
	{
		IMeshableVoxelBuffer c = o.chunk;
		auto blockskip = c.blockskip;

		CompressedMeshBuffer buffer;
		do buffer = meshBufferPool.get;
		while(buffer is null);

		buffer.chunkMax = c.dimensionsProper * c.voxelScale;

		Vector3f[64] verts, normals;

		for(int x = 0; x < c.dimensionsProper; x += blockskip)
		for(int y = 0; y < c.dimensionsProper; y += blockskip)
		for(int z = 0; z < c.dimensionsProper; z += blockskip)
		{
			Voxel voxel = c.get(x, y, z); // caused a crash, check fluid notes
			if(voxel.mesh != processor.glassMesh.id)
				continue;

			Voxel[6] neighbours;
			SideSolidTable[6] isSidesSolid;

			neighbours[VoxelSide.nx] = c.get(x - blockskip, y, z);
			neighbours[VoxelSide.px] = c.get(x + blockskip, y, z);
			neighbours[VoxelSide.ny] = c.get(x, y - blockskip, z);
			neighbours[VoxelSide.py] = c.get(x, y + blockskip, z);
			neighbours[VoxelSide.nz] = c.get(x, y, z - blockskip);
			neighbours[VoxelSide.pz] = c.get(x, y, z + blockskip);

			isSidesSolid[VoxelSide.nx] = processor.resources.getMesh(neighbours[VoxelSide.nx].mesh).isSideSolid(neighbours[VoxelSide.nx], VoxelSide.px);
			isSidesSolid[VoxelSide.px] = processor.resources.getMesh(neighbours[VoxelSide.px].mesh).isSideSolid(neighbours[VoxelSide.px], VoxelSide.nx);
			isSidesSolid[VoxelSide.ny] = processor.resources.getMesh(neighbours[VoxelSide.ny].mesh).isSideSolid(neighbours[VoxelSide.ny], VoxelSide.py);
			isSidesSolid[VoxelSide.py] = processor.resources.getMesh(neighbours[VoxelSide.py].mesh).isSideSolid(neighbours[VoxelSide.py], VoxelSide.ny);
			isSidesSolid[VoxelSide.nz] = processor.resources.getMesh(neighbours[VoxelSide.nz].mesh).isSideSolid(neighbours[VoxelSide.nz], VoxelSide.pz);
			isSidesSolid[VoxelSide.pz] = processor.resources.getMesh(neighbours[VoxelSide.pz].mesh).isSideSolid(neighbours[VoxelSide.pz], VoxelSide.nz);
		
			int vertCount;
			processor.glassMesh.generateMesh(voxel, blockskip, neighbours, isSidesSolid, Vector3i(x, y, z), verts, normals, vertCount);

			ubyte[4] colour = [255, 255, 255, 0];
			foreach(int i; 0 .. vertCount)
				buffer.add(verts[i] * c.voxelScale, normals[i], colour);
		}

		if(buffer.vertexCount == 0)
		{
			buffer.reset;
			meshBufferPool.give(buffer);
			c.meshBlocking(false, processor.id_);
			buffer = null;
		}
		MeshResult mr;
		mr.order = o;
		mr.buffer = buffer;
		results.send(mr);
	}
}

package struct MeshResult
{
	MeshOrder order;
	CompressedMeshBuffer buffer;
}

package enum maxVertices = 80_192;
package enum channels = 3;

package class CompressedMeshBuffer
{
	uint[] vertices;
	uint[] normals;
	ubyte[] colours;
	ushort vertexCount = 0;

	enum tenBitMax = 1023;

	private float chunkMax_ = 0f;
	@property float chunkMax() const { return chunkMax_; }
	@property void chunkMax(float cm)
	{
		chunkMax_ = cm;
		inv = 1f / cm;
		fit10Bit = tenBitMax * inv;
	}
	float inv = 0f;
	float fit10Bit = 0f;

	this()
	{
		vertices = new uint[](maxVertices);
		normals = new uint[](maxVertices);
		colours = new ubyte[](maxVertices*4);
	}

	void add(const uint vertex, const uint normal, const ubyte[4] colour)
	{
		vertices[vertexCount] = vertex;
		normals[vertexCount] = normal;
		colours[vertexCount*4 .. vertexCount*4 + 4] = colour[];
		vertexCount++;
	}

	void add(const Vector3f vertex, const Vector3f normal, const ubyte[4] colour, const ubyte vertexPack = 0, const ubyte normalPack = 0)
	{
		const float vx = clamp(vertex.x, 0f, chunkMax_) * fit10Bit;
		uint vxU = cast(uint)vx & tenBitMax;

		const float vy = clamp(vertex.y, 0f, chunkMax_) * fit10Bit;
		uint vyU = cast(uint)vy & tenBitMax;
		vyU <<= 10;

		const float vz = clamp(vertex.z, 0f, chunkMax_) * fit10Bit;
		uint vzU = cast(uint)vz & tenBitMax;
		vzU <<= 20;

		vertices[vertexCount] = vxU | vyU | vzU | (vertexPack << 30);

		const float nx = (((clamp(normal.x, -1f, 1f) + 1f) * 0.5f) * tenBitMax);
		const float ny = (((clamp(normal.y, -1f, 1f) + 1f) * 0.5f) * tenBitMax);
		const float nz = (((clamp(normal.z, -1f, 1f) + 1f) * 0.5f) * tenBitMax);

		const uint nxU = (cast(uint)nx & tenBitMax);
		const uint nyU = (cast(uint)ny & tenBitMax) << 10;
		const uint nzU = (cast(uint)nz & tenBitMax) << 20;

		normals[vertexCount] = nxU | nyU | nzU | (normalPack << 30);

		colours[vertexCount*4 .. vertexCount*4 + 4] = colour[];

		vertexCount++;
	}

	void reset() { vertexCount = 0; chunkMax_ = float.nan; inv = float.nan; fit10Bit = float.nan; }
}