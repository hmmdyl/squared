module squareone.voxelcontent.vegetation.processor;

import squareone.voxel;
import squareone.voxelcontent.vegetation.types;
import squareone.util.spec;
import squareone.terrain.gen.simplex;

import moxane.core;
import moxane.utils.pool;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;
import dlib.math.utils;
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

	package IVegetationVoxelTexture[] textures;
	package IVegetationVoxelMesh[ushort] meshes;
	package IVegetationVoxelMaterial[ushort] materials;

	private uint vao;

	this(IVegetationVoxelTexture[] textures)
	in(textures !is null)
	do {
		this.textures = textures;

		meshBufferPool = Pool!MeshBuffer(() => new MeshBuffer, 24, false);
		meshResults = new Channel!MeshResult;
	}

	~this()
	{
		import derelict.opengl3.gl3 : glDeleteVertexArrays;
		glDeleteVertexArrays(1, &vao);
	}

	void finaliseResources(Resources resources)
	{
		assert(resources !is null); 
		this.resources = resources;

		foreach(ushort x; 0 .. resources.meshCount)
		{
			IVegetationVoxelMesh vvm = cast(IVegetationVoxelMesh)resources.getMaterial(x);
			if(vvm is null) continue;
			meshes[x] = vvm;
		}
		meshes = meshes.rehash;


	}
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
		MeshBuffer buffer;
		do buffer = processor.meshBufferPool.get;
		while(buffer is null);

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

			if(isGrass(mesh.meshType))
			{
				float height = meshTypeToBlockHeight(mesh.meshType);
				colourBytes[3] = material.grassTexture;
				
				foreach(size_t vid, immutable Vector3f v; grassBundle3)
				{
					size_t tid = vid / grassPlane.length;
					Vector3f vertex = Vector3f(v.x, v.y, v.z);
					Vector2f texCoord = Vector2f(grassPlaneTexCoords[tid]);
					
					vertex = (vertex * Vector3f(1, height, 1)) * order.chunk.blockskip + Vector3f(x, y, z);
					if(shiftDown) vertex.y -= order.chunk.blockskip;
					vertex *= order.chunk.voxelScale;
					buffer.add(vertex, colourBytes, texCoord);
				}
			}
		}

		if(buffer.vertexCount == 0)
		{
			buffer.reset;
			processor.meshBufferPool.give(buffer);
			buffer = null;
			order.chunk.meshBlocking(false, processor.id_);

			MeshResult mr;
			mr.order = order;
			mr.buffer = null;
			processor.meshResults.send(mr);
		}
		else
		{
			MeshResult mr;
			mr.order = order;
			mr.buffer = buffer;
			processor.meshResults.send(mr);
		}
	}
}

private immutable Vector3f[] grassPlane = [
	Vector3f(0, 0, 0.5),
	Vector3f(1, 0, 0.5),
	Vector3f(1, 1, 0.5),
	Vector3f(1, 1, 0.5),
	Vector3f(0, 1, 0.5),
	Vector3f(0, 0, 0.5)
];

private Vector3f[] calculateGrassBundle(immutable Vector3f[] grassSinglePlane, uint numPlanes)
in(numPlanes > 0 && numPlanes <= 10)
do {
	Vector3f[] result = new Vector3f[](grassSinglePlane.length * numPlanes);
	size_t resultI;

	const float segment = 180f / numPlanes;
	foreach(planeNum; 0 .. numPlanes)
	{
		float rotation = segment * planeNum;
		Matrix4f rotMat = rotationMatrix!float(Axis.y, degtorad(rotation));

		foreach(size_t vid, immutable Vector3f v; grassSinglePlane)
		{
			Vector3f vT = (rotation * Vector4f(v.arrayof[0], v.arrayof[1], v.arrayof[2], 1.0f)).xyz;
			result[resultI++] = vT;
		}
	}

	return result;
}

private immutable Vector3f[] grassBundle3 = calculateGrassBundle(grassPlane, 3);

private immutable Vector2f[] grassPlaneTexCoords = [
	Vector2f(0.25, 0),
	Vector2f(0.75, 0),
	Vector2f(0.75, 1),
	Vector2f(0.75, 1),
	Vector2f(0.25, 1),
	Vector2f(0.25, 0),
];

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