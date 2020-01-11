module squareone.content.voxel.fluid.meshers;

import squareone.voxel;
import squareone.content.voxel.fluid.processor;
import squareone.content.voxel.fluid.types;

import moxane.core;
import moxane.utils.maybe;

import dlib.math.vector;

import std.random;
import std.concurrency;
import std.algorithm;
import core.atomic;

package final class Mesher : IMesher
{
	private IChannel!MeshOrder source_;
	@property IChannel!MeshOrder source() { return source_; }

	private shared float averageMeshTime_ = 0f;
	@property float averageMeshTime() { return atomicLoad(averageMeshTime_); }
	private @property void averageMeshTime(float n) { atomicStore(averageMeshTime_, n); }

	private shared bool parked_, terminated_;
	@property bool parked() const { return atomicLoad(parked_); }
	private @property void parked(bool n) { atomicStore(parked_, n); }
	@property bool terminated() const { return atomicLoad(terminated_); }
	private @property void terminated(bool n) { atomicStore(terminated_, n); }

	private Tid thread;

	private FluidProcessor processor;
	private Resources resources;

	this(FluidProcessor processor, Resources resources, ushort fluidID, IChannel!MeshOrder source, immutable MeshID[] meshOn)
	in(processor !is null) in(resources !is null) in(source !is null)
	{
		this.processor = processor;
		this.resources = resources;
		this.source_ = source;
		
		parked = true;
		terminated = false;

		thread = spawn(&worker, cast(shared)this, fluidID, meshOn);
	}

	void kick() { send(thread, true); }
	void terminate() { send(thread, false); }
}

private void worker(shared Mesher meshers, ushort fluidID, immutable MeshID[] meshOn)
{
	Mesher mesher = cast(Mesher)meshers;
	Log log = mesher.processor.moxane.services.getAOrB!(VoxelLog, Log);

	enum threadName = FluidProcessor.stringof ~ Mesher.stringof;
	scope(failure) log.write(Log.Severity.panic, "Panic in " ~ threadName);

	while(!mesher.terminated)
	{
		receive(
			(bool m)
			{
				if(!m)
				{
					mesher.terminated = true;
					return;
				}

				mesher.parked = false;
				scope(exit) mesher.parked = true;

				bool consuming = true;
				while(consuming)
				{
					Maybe!MeshOrder order = mesher.source_.tryGet;
					if(order.isNull) consuming = false;
					else
					{
						operate(*order.unwrap, mesher, meshOn, fluidID);
					}
				}
			}
		);
	}
}

private void operate(MeshOrder o, Mesher mesher, immutable MeshID[] meshOn, MeshID fluidID)
{
	IMeshableVoxelBuffer c = o.chunk;
	immutable int blockskip = c.blockskip;
	immutable int chunkDimLod = c.dimensionsProper * c.blockskip;

	MeshBuffer buffer;
	do buffer = mesher.processor.meshBufferPool.get;
	while(buffer is null);

	for(int x = 0; x < chunkDimLod; x += blockskip)
	for(int y = 0; y < chunkDimLod; y += blockskip)
	for(int z = 0; z < chunkDimLod; z += blockskip)
	{
		Voxel v = c.get(x, y, z);
		Voxel[6] neighbours;
		Voxel[4] diagNeighbours, diagNeighboursUpper;

		neighbours[VoxelSide.nx] = c.get(x - blockskip, y, z);
		neighbours[VoxelSide.px] = c.get(x + blockskip, y, z);
		neighbours[VoxelSide.ny] = c.get(x, y - blockskip, z);
		neighbours[VoxelSide.py] = c.get(x, y + blockskip, z);
		neighbours[VoxelSide.nz] = c.get(x, y, z - blockskip);
		neighbours[VoxelSide.pz] = c.get(x, y, z + blockskip);

		diagNeighbours[0] = c.get(x - blockskip, y, z - blockskip);
		diagNeighbours[1] = c.get(x - blockskip, y, z + blockskip);
		diagNeighbours[2] = c.get(x + blockskip, y, z - blockskip);
		diagNeighbours[3] = c.get(x + blockskip, y, z + blockskip);

		diagNeighboursUpper[0] = c.get(x - blockskip, y + blockskip, z - blockskip);
		diagNeighboursUpper[1] = c.get(x - blockskip, y + blockskip, z + blockskip);
		diagNeighboursUpper[2] = c.get(x + blockskip, y + blockskip, z - blockskip);
		diagNeighboursUpper[3] = c.get(x + blockskip, y + blockskip, z + blockskip);

		void addVoxel(bool isOverrun)
		{
			SideSolidTable[6] isSideSolid;
			Vector3f vbias = Vector3f(x, y, z);

			SideSolidTable doMeshSide(int side)
			{
				if(isOverrun)
					if(side == VoxelSide.py) 
						return SideSolidTable.notSolid;

				foreach(m; meshOn)
					if(neighbours[side].mesh == m)
						return SideSolidTable.notSolid;
				return SideSolidTable.solid;
			}

			isSideSolid[VoxelSide.nx] = neighbours[VoxelSide.nx].mesh == fluidID ? SideSolidTable.solid : doMeshSide(VoxelSide.nx); //: processor.resources.getMesh(neighbours[VoxelSide.nx].mesh).isSideSolid(neighbours[VoxelSide.nx], VoxelSide.px);
			isSideSolid[VoxelSide.px] = neighbours[VoxelSide.px].mesh == fluidID ? SideSolidTable.solid : doMeshSide(VoxelSide.px);//: processor.resources.getMesh(neighbours[VoxelSide.px].mesh).isSideSolid(neighbours[VoxelSide.px], VoxelSide.nx);
			isSideSolid[VoxelSide.ny] = neighbours[VoxelSide.ny].mesh == fluidID ? SideSolidTable.solid : doMeshSide(VoxelSide.ny);//: processor.resources.getMesh(neighbours[VoxelSide.ny].mesh).isSideSolid(neighbours[VoxelSide.ny], VoxelSide.py);
			isSideSolid[VoxelSide.py] = neighbours[VoxelSide.py].mesh == fluidID ? SideSolidTable.solid : doMeshSide(VoxelSide.py);//: processor.resources.getMesh(neighbours[VoxelSide.py].mesh).isSideSolid(neighbours[VoxelSide.py], VoxelSide.ny);
			isSideSolid[VoxelSide.nz] = neighbours[VoxelSide.nz].mesh == fluidID ? SideSolidTable.solid : doMeshSide(VoxelSide.nz);//: processor.resources.getMesh(neighbours[VoxelSide.nz].mesh).isSideSolid(neighbours[VoxelSide.nz], VoxelSide.pz);
			isSideSolid[VoxelSide.pz] = neighbours[VoxelSide.pz].mesh == fluidID ? SideSolidTable.solid : doMeshSide(VoxelSide.pz);//: processor.resources.getMesh(neighbours[VoxelSide.pz].mesh).isSideSolid(neighbours[VoxelSide.pz], VoxelSide.nz);

			void addTriangle(ushort[3] indices, int dir)
			{
				buffer.add((cubeVertices[indices[0]] * blockskip + vbias) * c.voxelScale, cubeNormals[dir], [0,0,0,0]);
				buffer.add((cubeVertices[indices[1]] * blockskip + vbias) * c.voxelScale, cubeNormals[dir], [0,0,0,0]);
				buffer.add((cubeVertices[indices[2]] * blockskip + vbias) * c.voxelScale, cubeNormals[dir], [0,0,0,0]);
			}
			void addSide(int dir)
			{
				addTriangle(cubeIndices[dir][0], dir);
				addTriangle(cubeIndices[dir][1], dir);
			}

			if(isSideSolid[VoxelSide.nx] != SideSolidTable.solid) addSide(VoxelSide.nx);
			if(isSideSolid[VoxelSide.px] != SideSolidTable.solid) addSide(VoxelSide.px);
			if(isSideSolid[VoxelSide.ny] != SideSolidTable.solid) addSide(VoxelSide.ny);
			if(isSideSolid[VoxelSide.py] != SideSolidTable.solid) addSide(VoxelSide.py);
			if(isSideSolid[VoxelSide.nz] != SideSolidTable.solid) addSide(VoxelSide.nz);
			if(isSideSolid[VoxelSide.pz] != SideSolidTable.solid) addSide(VoxelSide.pz);
		}

		if(v.mesh == fluidID)
			addVoxel(false);
		if(v.mesh != fluidID && v.mesh != 0)
		{
			if(any!((Voxel v) => v.mesh == fluidID)(neighbours[]))
				addVoxel(true);
			if(count!((Voxel v) => v.mesh == fluidID)(diagNeighbours[]) > 0 && count!((Voxel v) => v.mesh == fluidID)(diagNeighboursUpper[]) == 0)
				addVoxel(true);
		}
	}

	if(buffer.vertexCount == 0)
	{
		buffer.reset;
		mesher.processor.meshBufferPool.give(buffer);
		buffer = null;

		MeshResult mr;
		mr.order = o;
		mr.buffer = null;
		mesher.processor.meshResults.send(mr);
	}
	else
	{
		MeshResult mr;
		mr.order = o;
		mr.buffer = buffer;
		mesher.processor.meshResults.send(mr);
	}
}

package struct MeshResult
{
	MeshOrder order;
	MeshBuffer buffer;
}

package class MeshBuffer
{
	enum elements = 2^^14;

	Vector3f[] vertices;
	Vector3f[] normals;
	ubyte[] colours;
	int vertexCount;

	this()
	{
		vertices = new Vector3f[](elements);
		normals = new Vector3f[](elements);
		colours = new ubyte[](elements*4);
	}

	void add(Vector3f vertex, Vector3f normal, ubyte[4] colour)
	{
		vertices[vertexCount] = vertex;
		normals[vertexCount] = normal;
		colours[vertexCount * 4 .. vertexCount * 4 + 4] = colour[];
		vertexCount++;
	}

	void reset() { vertexCount = 0; }
}

private immutable Vector3f[8] cubeVertices = [
	Vector3f(0, 0, 0), // ind0
	Vector3f(1, 0, 0), // ind1
	Vector3f(0, 0, 1), // ind2
	Vector3f(1, 0, 1), // ind3
	Vector3f(0, 1, 0), // ind4
	Vector3f(1, 1, 0), // ind5
	Vector3f(0, 1, 1), // ind6
	Vector3f(1, 1, 1)  // ind7
];

private immutable ushort[3][2][6] cubeIndices = [
	[[0, 2, 6], [6, 4, 0]], // -X
	[[7, 3, 1], [1, 5, 7]], // +X
	[[0, 1, 3], [3, 2, 0]], // -Y
	[[7, 5, 4], [4, 6, 7]], // +Y
	[[5, 1, 0], [0, 4, 5]], // -Z
	[[2, 3, 7], [7, 6, 2]]  // +Z
];

private immutable Vector3f[6] cubeNormals = [
	Vector3f(-1, 0, 0),
	Vector3f(1, 0, 0),
	Vector3f(0, -1, 0),
	Vector3f(0, 1, 0),
	Vector3f(0, 0, -1),
	Vector3f(0, 0, 1)
];