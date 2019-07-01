module squareone.voxelcontent.vegetation.processor;

import squareone.voxel;
import squareone.voxelcontent.vegetation.types;
import squareone.util.spec;
import squareone.terrain.gen.simplex;

import moxane.core;
import moxane.utils.pool;
import moxane.graphics.texture;
import moxane.graphics.effect;
import moxane.graphics.renderer;

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
	private enum mesherCount = 1;
	private Mesher[] meshers;
	private int meshBarrel;
	private Pool!(RenderData*) renderDataPool;

	package IVegetationVoxelTexture[] textures;
	package IVegetationVoxelMesh[ushort] meshes;
	package IVegetationVoxelMaterial[ushort] materials;

	private Texture2DArray textureArray;

	private uint vao;
	private Effect effect;

	this(Moxane moxane, IVegetationVoxelTexture[] textures)
	in(moxane !is null)
	in(textures !is null)
	do {
		this.textures = textures;
		this.moxane = moxane;

		meshBufferPool = Pool!MeshBuffer(() => new MeshBuffer, 24, false);
		meshResults = new Channel!MeshResult;
		renderDataPool = Pool!(RenderData*)(() => new RenderData, 64);
	}

	~this()
	{
		import derelict.opengl3.gl3 : glDeleteVertexArrays;
		glDeleteVertexArrays(1, &vao);

		foreach(x; 0 .. meshers.length)
		{
			Mesher m = meshers[x];
			destroy(m);
			meshers[x] = null;
		}
	}

	void finaliseResources(Resources resources)
	{
		assert(resources !is null); 
		this.resources = resources;

		foreach(ushort x; 0 .. resources.meshCount)
		{
			IVegetationVoxelMesh vvm = cast(IVegetationVoxelMesh)resources.getMesh(x);
			if(vvm is null) continue;
			meshes[x] = vvm;
		}
		meshes = meshes.rehash;

		string[] textureFiles = new string[](textures.length);
		foreach(size_t x, IVegetationVoxelTexture texture; textures)
		{
			texture.id = cast(ubyte)x;
			textureFiles[x] = texture.file;
		}
		textureArray = new Texture2DArray(textureFiles, false, Filter.nearest, Filter.nearest, true);

		foreach(ushort x; 0 .. resources.materialCount)
		{
			IVegetationVoxelMaterial vvm = cast(IVegetationVoxelMaterial)resources.getMaterial(x);
			if(vvm is null) continue;
			vvm.loadTextures(this);
			materials[x] = vvm;
		}
		materials.rehash;

		foreach(x; 0 .. mesherCount)
			meshers ~= new Mesher(this);

		import std.file : readText;
		import derelict.opengl3.gl3 : glGenVertexArrays, GL_FRAGMENT_SHADER, GL_VERTEX_SHADER;
		glGenVertexArrays(1, &vao);

		Log log = moxane.services.get!(Log);
		Shader vs = new Shader, fs = new Shader;
		vs.compile(readText(AssetManager.translateToAbsoluteDir("content/shaders/veggieProcessor.vs.glsl")), GL_VERTEX_SHADER, log);
		fs.compile(readText(AssetManager.translateToAbsoluteDir("content/shaders/veggieProcessor.fs.glsl")), GL_FRAGMENT_SHADER, log);
		effect = new Effect(moxane, VegetationProcessor.stringof);
		effect.attachAndLink(vs, fs);
		effect.bind;
		effect.findUniform("ModelViewProjection");
		effect.findUniform("Model");
		effect.findUniform("Textures");
		effect.unbind;
	}

	private bool isRdNull(IMeshableVoxelBuffer vb) { return vb.renderData[id_] is null; }
	private RenderData* getRD(IMeshableVoxelBuffer vb) { return cast(RenderData*)vb.renderData[id_]; }

	void meshChunk(MeshOrder o)
	{
		meshers[meshBarrel++].orders.send(o);
		if(meshBarrel >= mesherCount) meshBarrel = 0;
	}

	void removeChunk(IMeshableVoxelBuffer c)
	{
		if(isRdNull(c)) return;

		RenderData* rd = getRD(c);
		rd.destroy;
		renderDataPool.give(rd);

		c.renderData[id_] = null;
	}

	void updateFromManager()
	{}

	void performUploads()
	{
		while(!meshResults.empty)
		{
			Optional!MeshResult meshResult = meshResults.tryGet;
			if(meshResult == none) return;

			MeshResult result = *unwrap(meshResult);

			if(result.buffer is null)
			{
				if(!isRdNull(result.order.chunk))
					removeChunk(result.order.chunk);
				continue;
			}

			bool hasRD = !isRdNull(result.order.chunk);
			RenderData* rd;
			if(hasRD)
				rd = getRD(result.order.chunk);
			else
			{
				rd = renderDataPool.get;
				rd.create;
				result.order.chunk.renderData[id_] = cast(void*)rd;
			}

			rd.vertexCount = result.buffer.vertexCount;

			import derelict.opengl3.gl3;
			
			glBindBuffer(GL_ARRAY_BUFFER, rd.vertex);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * Vector3f.sizeof, result.buffer.vertices.ptr, GL_STATIC_DRAW);
			
			glBindBuffer(GL_ARRAY_BUFFER, rd.colour);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, result.buffer.colours.ptr, GL_STATIC_DRAW);

			glBindBuffer(GL_ARRAY_BUFFER, rd.texCoords);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * Vector2f.sizeof, result.buffer.texCoords.ptr, GL_STATIC_DRAW);

			glBindBuffer(GL_ARRAY_BUFFER, 0);

			result.order.chunk.meshBlocking(false, id_);
			result.buffer.reset;
			meshBufferPool.give(result.buffer);
		}
	}

	Renderer renderer;
	void prepareRender(Renderer renderer)
	{
		this.renderer = renderer;
		import derelict.opengl3.gl3;

		performUploads;
		glBindVertexArray(vao);

		foreach(x; 0 .. 3)
			glEnableVertexAttribArray(x);

		effect.bind;
		textureArray.bind;
		effect["Textures"].set(0);
	}

	void render(IMeshableVoxelBuffer chunk, ref LocalContext lc, ref uint drawCalls, ref uint numVerts)
	{
		RenderData* rd = getRD(chunk);
		if(rd is null) return;

		Matrix4f m = translationMatrix(chunk.transform.position);
		Matrix4f nm = lc.model * m;
		Matrix4f mvp = lc.projection * lc.view * nm;
		Matrix4f mv = lc.view * nm;

		effect["ModelViewProjection"].set(&mvp);
		effect["Model"].set(&nm);

		import derelict.opengl3.gl3;
		glBindBuffer(GL_ARRAY_BUFFER, rd.vertex);
		glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, rd.colour);
		glVertexAttribIPointer(1, 4, GL_UNSIGNED_BYTE, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, rd.texCoords);
		glVertexAttribPointer(2, 2, GL_FLOAT, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		glDrawArrays(GL_TRIANGLES, 0, rd.vertexCount);
		numVerts += rd.vertexCount;
		drawCalls++;
	}

	void endRender()
	{
		import derelict.opengl3.gl3;
		foreach(x; 0 .. 3)
			glDisableVertexAttribArray(x);
		effect.unbind;
		glBindVertexArray(0);
	}

	ubyte textureID(string tech)
	{
		foreach(IVegetationVoxelTexture t; textures)
			if(t.technical == tech)
				return t.id;
		return 0;
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
			
			IVegetationVoxelMesh* meshPtr = voxel.mesh in processor.meshes;
			if(meshPtr is null) continue;
			IVegetationVoxelMesh mesh = *meshPtr;

			Voxel ny = order.chunk.get(x, y - order.chunk.blockskip, z);
			const bool shiftDown = processor.resources.getMesh(ny.mesh).isSideSolid(ny, VoxelSide.py) != SideSolidTable.solid;

			const Vector3f colour = voxel.extractColour;
			ubyte[4] colourBytes = [
				cast(ubyte)(/*colour.x * */28),
				cast(ubyte)(/*colour.y * */248),
				cast(ubyte)(/*colour.z * */78),
				0
			];

			IVegetationVoxelMaterial* materialPtr = voxel.material in processor.materials;
			if(materialPtr is null) throw new Exception("Yeetus");
			IVegetationVoxelMaterial material = *materialPtr;

			if(mesh.meshType == MeshType.grass)
			{
				GrassVoxel gv = GrassVoxel(voxel);
				// TODO: implement height
				float height = gv.blockHeight;
				colourBytes[3] = material.grassTexture;

				//gv.offset = 2;

				Matrix4f rotMat = rotationMatrix(Axis.y, degtorad((60f / 8f) * gv.offset)) * translationMatrix(Vector3f(-0.5f, -0.5f, -0.5f));
				Matrix4f retTraMat = translationMatrix(Vector3f(0.5f, 0.5f, 0.5f));
				
				foreach(size_t vid, immutable Vector3f v; grassBundle3)
				{
					size_t tid = vid % grassPlane.length;
					Vector2f texCoord = Vector2f(grassPlaneTexCoords[tid]);

					//Vector3f vertex = Vector3f(v.x, v.y, v.z);
					Vector3f vertex = ((Vector4f(v.x, v.y, v.z, 1f) * rotMat) * retTraMat).xyz;

					import std.math;
					ubyte offset = gv.offset;
					float xOffset = offset == 0 ? 0f : cos(degtorad((360f / 7f) * (offset-1))) * 0.25f;
					float yOffset = offset == 0 ? 0f : sin(degtorad((360f / 7f) * (offset-1))) * 0.25f;

					vertex += Vector3f(xOffset, 0f, yOffset);
					//vertex -= Vector3f(0.25f, 0f, 0.25f);
					
					vertex = (vertex * Vector3f(1f, height + (height * gv.heightOffset), 1f)) * order.chunk.blockskip + Vector3f(x, y, z);
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

/+private immutable Vector3f[] grassPlane = [
	Vector3f(0, 0, 0.5),
	Vector3f(1, 0, 0.5),
	Vector3f(1, 1, 0.5),
	Vector3f(1, 1, 0.5),
	Vector3f(0, 1, 0.5),
	Vector3f(0, 0, 0.5)
];+/

/+private immutable Vector3f[] grassPlane = [
	Vector3f(-0.2f, 0, 0.5),
	Vector3f(1.2f, 0, 0.5),
	Vector3f(1.2f, 1, 0.5),
	Vector3f(1.2f, 1, 0.5),
	Vector3f(-0.2f, 1, 0.5),
	Vector3f(-0.2f, 0, 0.5)
];+/

private immutable Vector3f[] grassPlane = [
	Vector3f(-0.2f, 0, 0.15),
	Vector3f(1.2f, 0, 0.15),
	Vector3f(1.2f, 1, 0.95),
	Vector3f(1.2f, 1, 0.95),
	Vector3f(-0.2f, 1, 0.95),
	Vector3f(-0.2f, 0, 0.15)
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
		Matrix4f rotMat = rotationMatrix(Axis.y, degtorad(rotation)) * translationMatrix(Vector3f(-0.5f, -0.5f, -0.5f));

		foreach(size_t vid, immutable Vector3f v; grassSinglePlane)
		{
			Vector3f vT = ((Vector4f(v.x, v.y, v.z, 1f) * rotMat) * translationMatrix(Vector3f(0.5f, 0.5f, 0.5f))).xyz;
			result[resultI++] = vT;
		}
	}

	return result;
}

private __gshared static Vector3f[] grassBundle3;

shared static this() 
{ 
	grassBundle3 = calculateGrassBundle(grassPlane, 3);
	import std.stdio; writeln(grassBundle3); 
}

private immutable Vector2f[] grassPlaneTexCoords = [
	/+Vector2f(0.25, 0),
	Vector2f(0.75, 0),
	Vector2f(0.75, 1),
	Vector2f(0.75, 1),
	Vector2f(0.25, 1),
	Vector2f(0.25, 0),+/
	Vector2f(0, 0),
	Vector2f(1, 0),
	Vector2f(1, 1),
	Vector2f(1, 1),
	Vector2f(0, 1),
	Vector2f(0, 0),
];

private enum bufferMaxVertices = 80_192;

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