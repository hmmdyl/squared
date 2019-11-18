module squareone.voxelcontent.vegetation.mesher;

import squareone.voxel;
import squareone.voxelcontent.vegetation.processor;

import moxane.core;

import dlib.math.vector;
import dlib.math.matrix;

import std.concurrency;
import core.atomic;

package final class Mesher : IMesher
{
	private IChannel!MeshOrder source_;
	@property IChannel!MeshOrder source() { return source_; }

	private shared float averageMeshTime_ = 0f;
	@property float averageMeshTime() { return atomicLoad(averageMeshTime_); }

	private shared bool parked_ = true, terminated_ = false;
	@property bool parked() const { return atomicLoad(parked_); }
	@property bool terminated() const { return atomicLoad(terminated_); }

	private Tid thread;

	VegetationProcessor processor;

	this(VegetationProcessor processor, IChannel!MeshOrder source)
	in(processor !is null) in(source !is null)
	{
		this.source_ = source;
		this.processor = processor;

		thread = spawn(&worker, cast(shared)this, cast(shared)processor); 
	}

	void kick() { send(thread, true); }
	void terminate() { send(thread, false); }
}

private void worker(shared Mesher mesherS, shared VegetationProcessor processorS)
in(mesherS !is null) in(processorS !is null)
{

}

struct MeshResult
{
	MeshOrder order;
	MeshBuffer buffer;
}

package enum bufferMaxVertices = 2 ^^ 14;

package final class MeshBuffer
{
	Vector3f[] vertices;
	ubyte[] colours;
	Vector2f[] texCoords;
	ushort vertexCount;

	this()
	{
		vertices.length = bufferMaxVertices;
		colours.length = bufferMaxVertices * 4;
		texCoords.length = bufferMaxVertices;
	}

	void reset() { vertexCount = 0; }

	void add(Vector3f vertex, ubyte[4] colour, Vector2f texCoord)
	{
		vertices[vertexCount] = vertex;
		colours[vertexCount * 4 .. vertexCount * 4 + 4] = colour[];
		texCoords[vertexCount] = texCoord;
		vertexCount++;
	}
}