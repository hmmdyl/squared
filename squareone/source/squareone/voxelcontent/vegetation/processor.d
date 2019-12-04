module squareone.voxelcontent.vegetation.processor;

import squareone.voxelcontent.vegetation.precalc;
import squareone.voxelcontent.vegetation.types;
import squareone.voxelcontent.vegetation.mesher;

import squareone.voxel;
import squareone.util.spec;

import moxane.core;
import moxane.utils.pool;
import moxane.graphics.texture;
import moxane.graphics.effect;
import moxane.graphics.renderer;
import moxane.utils.maybe;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;
import dlib.math.utils;
import core.thread;
import std.datetime.stopwatch;

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
	private Pool!(RenderData*) renderDataPool;

	package IVegetationVoxelTexture[] textures;
	package IVegetationVoxelMesh[ushort] meshes;
	package IVegetationVoxelMaterial[ushort] materials;

	private Texture2DArray textureArray;

	private uint vao;
	private Effect effect;
	private float waveTime = 1f;

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
		effect.findUniform("ModelView");
		effect.findUniform("Model");
		effect.findUniform("Textures");
		effect.findUniform("Time");
		effect.findUniform("CompChunkMax");
		effect.findUniform("CompFit10B");
		effect.findUniform("CompOffset");
		effect.unbind;
	}

	private bool isRdNull(IMeshableVoxelBuffer vb) { return vb.renderData[id_] is null; }
	private RenderData* getRD(IMeshableVoxelBuffer vb) { return cast(RenderData*)vb.renderData[id_]; }

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

	private uint[] vertexCompressionBuffer = new uint[](bufferMaxVertices);
	private uint[] texCoordCompressionBuffer = new uint[](bufferMaxVertices);

	void performUploads()
	{
		StopWatch uploadSw = StopWatch(AutoStart.yes);
		while(uploadSw.peek.total!"msecs" < 4 && !meshResults.empty)
		{
			Maybe!MeshResult meshResult = meshResults.tryGet;
			if(meshResult.isNull) return;

			MeshResult result = *meshResult.unwrap();

			if(result.buffer is null)
			{
				if(!isRdNull(result.order.chunk))
					removeChunk(result.order.chunk);
				result.order.chunk.meshBlocking(false, id_);
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

			vertexCompressionBuffer[] = 0;
			texCoordCompressionBuffer[] = 0;

			rd.chunkMax = result.order.chunk.dimensionsTotal * result.order.chunk.blockskip * result.order.chunk.voxelScale;
			float invCM = 1f / rd.chunkMax;
			rd.offset = result.order.chunk.voxelScale;
			rd.fit10BitScale = 1023f * invCM;

			foreach(i; 0 .. result.buffer.vertexCount)
			{
				const Vector3f vertex = result.buffer.vertices[i] + rd.offset;

				float vx = clamp(vertex.x, 0f, rd.chunkMax) * rd.fit10BitScale;
				uint vxU = cast(uint)vx & 1023;

				float vy = clamp(vertex.y, 0f, rd.chunkMax) * rd.fit10BitScale;
				uint vyU = cast(uint)vy & 1023;
				vyU <<= 10;

				float vz = clamp(vertex.z, 0f, rd.chunkMax) * rd.fit10BitScale;
				uint vzU = cast(uint)vz & 1023;
				vzU <<= 20;

				vertexCompressionBuffer[i] = vxU | vyU | vzU;

				const Vector2f texCoord = result.buffer.texCoords[i];

				enum texCoordFit = ushort.max;

				float tx = clamp(texCoord.x, 0f, 1f) * texCoordFit;
				uint txU = cast(uint)tx & 0xFFFF;
				float ty = clamp(texCoord.y, 0f, 1f) * texCoordFit;
				uint tyU = cast(uint)ty & 0xFFFF;
				tyU <<= 16;

				texCoordCompressionBuffer[i] = txU | tyU;
			}
			
			glBindBuffer(GL_ARRAY_BUFFER, rd.vertex);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, vertexCompressionBuffer.ptr, GL_STATIC_DRAW);
			
			glBindBuffer(GL_ARRAY_BUFFER, rd.colour);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, result.buffer.colours.ptr, GL_STATIC_DRAW);

			glBindBuffer(GL_ARRAY_BUFFER, rd.texCoords);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, texCoordCompressionBuffer.ptr, GL_STATIC_DRAW);
			
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
		waveTime += moxane.deltaTime;
		effect["Time"].set(waveTime);
	}

	void render(IMeshableVoxelBuffer chunk, ref LocalContext lc, ref uint drawCalls, ref uint numVerts)
	{
		if(!(lc.type == PassType.scene || lc.type == PassType.scene)) return;

		RenderData* rd = getRD(chunk);
		if(rd is null) return;

		Matrix4f m = translationMatrix(chunk.transform.position);
		Matrix4f nm = lc.model * m;
		Matrix4f mvp = lc.projection * lc.view * nm;
		Matrix4f mv = lc.view * nm;

		effect["ModelViewProjection"].set(&mvp);
		effect["ModelView"].set(&mv);
		effect["Model"].set(&nm);

		effect["CompChunkMax"].set(rd.chunkMax);
		effect["CompFit10B"].set(rd.fit10BitScale);
		effect["CompOffset"].set(rd.offset);

		import derelict.opengl3.gl3;
		glBindBuffer(GL_ARRAY_BUFFER, rd.vertex);
		glVertexAttribPointer(0, 4, GL_UNSIGNED_INT_2_10_10_10_REV, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, rd.colour);
		glVertexAttribIPointer(1, 4, GL_UNSIGNED_BYTE, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, rd.texCoords);
		glVertexAttribIPointer(2, 2, GL_UNSIGNED_SHORT, 0, null);
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

	enum minMeshersCount = 1;
	@property size_t minMeshers() const { return minMeshersCount; }
	IMesher requestMesher(IChannel!MeshOrder source) {return new Mesher(this, source);}
	void returnMesher(IMesher m) {}
}