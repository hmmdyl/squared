module squareone.voxelcontent.vegetation.processor;

import squareone.voxel;
import squareone.voxelcontent.vegetation.types;
import squareone.util.spec;
import squareone.terrain.gen.simplex;

import moxane.core;
import moxane.utils.pool;

import dlib.math.vector;
import core.thread;
import optional : Optional, unwrap, none;

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

	package IVegetationVoxelMesh[] meshes;
	package IVegetationVoxelMaterial[] materials;
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

	private OpenSimplexNoise!float simplex;

	this(VegetationProcessor processor)
	in(processor !is null)
	do {
		this.processor = processor;
		orders = new Channel!MeshOrder;
		simplex = new OpenSimplexNoise!float;
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
		for(int x = 0; x < order.chunk.dimensionsProper; x += order.chunk.blockskip)
		for(int y = 0; y < order.chunk.dimensionsProper; y += order.chunk.blockskip)
		for(int z = 0; z < order.chunk.dimensionsProper; z += order.chunk.blockskip)
		{
			Voxel voxel = order.chunk.get(x, y, z);

			IVegetationVoxelMesh mesh = processor.meshes[voxel.mesh];
			if(mesh is null) continue;

			Voxel ny = order.chunk.get(x, y - order.chunk.blockskip, z);
			const bool shiftDown = processor.resources.getMesh(ny.mesh).isSideSolid(ny, VoxelSide.py) != SideSolidTable.solid;

			const Vector3f colour = voxel.extractColour;
			ubyte[4] colourBytes = [
				cast(ubyte)(colour.x * 255),
				cast(ubyte)(colour.y * 255),
				cast(ubyte)(colour.z * 255),
				0
			];

			IVegetationVoxelMaterial material = processor.materials[voxel.material];
			if(material is null) throw new Exception("Yeetus");

			if(mesh.meshType == MeshType.grass)
			{
				colourBytes[3] = material.grassTexture;
				
			}
		}
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
		vertices[vertexCount] = vertex;
		colours[vertexCount * 4 .. vertexCount * 4 + 4] = colour[];
		texCoords[vertexCount] = texCoord;
		vertexCount++;
	}
}

private final class MeshBufferHost
{

}