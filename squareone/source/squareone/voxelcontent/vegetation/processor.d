module squareone.voxelcontent.vegetation.processor;

import squareone.voxel;
import squareone.voxelcontent.vegetation.types;
import squareone.util.spec;

import moxane.core;
import moxane.utils.pool;

import dlib.math.vector;
import core.thread;

final class VegetationProcessor : IProcessor
{
	private ubyte id_;
	@property ubyte id() { return id_; }
	@property void id(ubyte n) { id_ = n; }
	mixin(VoxelContentQuick!("squareOne:voxel:processor:vegetation", "", appName, dylanGrahamName));

	Moxane moxane;
	Resources resources;

	package Pool!MeshBuffer meshBufferPool;
	package Channel!MeshResult meshResults;
}

private struct MeshResult
{
	MeshOrder order;
	MeshBuffer buffer;
}

private final class Mesher
{
	VegetationProcessor processor;

	Channel!MeshOrder orders;
	private bool terminate;
	private Thread thread;

	this(VegetationProcessor processor)
	in(processor !is null)
	do {
		this.processor = processor;
		orders = new Channel!MeshOrder;
		thread = new Thread(&worker);
		thread.name = VegetationProcessor.stringof ~ " " ~ Mesher.stringof;
		thread.isDaemon = true;
		thread.start;
	}

	~this()
	{
		if(thread !is null && thread.isRunning)
		{
			terminate = true;
			orders.notifyUnsafe;
			thread.join;
		}
	}

	private void worker()
	{
		try
		{
			while(!terminate)
			{
				Optional!MeshOrder order = orders.await;
				if(MeshOrder* o = order.unwrap)
					execute(*o);
				else return;
			}
		}
		catch(Throwable t)
		{
			import std.conv : to;
			Log log = processor.moxane.services.get!Log;
			log.write(Log.Severity.error, "Exception in " ~ thread.name ~ "\n\tMessage: " ~ to!string(t.message) ~ "\n\tLine: " ~ to!string(t.line) ~ "\n\tStacktrace: " ~ t.info.toString);
			log.write(Log.Severity.error, "Thread will not be restarted.");
		}
	}

	private void execute(MeshOrder order)
	{
		
	}
}

private enum bufferMaxVertices = 8_192;

private final class MeshBuffer
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
		vertices[vertexCount] = v;
		colours[vertexCount * 4 .. vertexCount * 4 + 4] = colour[];
		texCoords[vertexCount] = texCoord;
		vertexCount++;
	}
}

private final class MeshBufferHost
{

}