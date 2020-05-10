module squareone.client.content.voxel.vegetation.processor;

import squareone.client.voxel;
import squareone.common.content.voxel.vegetation;
import squareone.common.voxel;

import moxane.core;
import moxane.graphics.redo;
import moxane.utils.pool;
import moxane.utils.maybe;

import derelict.opengl3.gl3;
import dlib.math;
import std.algorithm.searching : find;
import std.datetime.stopwatch;

@safe:

final class VegetationProcessor : VegetationProcessorBase, IClientProcessor
{
	private Pool!(RenderData*) renderDataPool;

	package IVegetationVoxelTexture[] textures;
	package IVegetationVoxelMesh[ushort] meshes;
	package IVegetationVoxelMaterial[ushort] materials;

	private Texture2DArray textureArray;

	private GLuint vao;
	private Effect effect;

	private uint[] vertexCompressionBuffer = new uint[](bufferMaxVertices);
	private uint[] texCoordCompressionBuffer = new uint[](bufferMaxVertices);

	private float waveTime = 0f;

	this(Moxane moxane, VoxelRegistry registry, IVegetationVoxelTexture[] textures) @trusted
	in { assert(moxane !is null); assert(registry !is null); assert(textures !is null); }
	do {
		super(moxane, registry);
		this.textures = textures;

		meshBufferPool = Pool!MeshBuffer(() @trusted => new MeshBuffer, 24, false);
		meshResults = new Channel!MeshResult;
		renderDataPool = Pool!(RenderData*)(() @trusted => new RenderData, 64);
	
		glGenVertexArrays(1, &vao);
		
		Log log = moxane.services.getAOrB!(GraphicsLog, Log);
		auto vs = new Shader(AssetManager.translateToAbsoluteDir("content/shaders/veggieProcessor.vs.glsl"), GL_VERTEX_SHADER, log);
		auto fs = new Shader(AssetManager.translateToAbsoluteDir("content/shaders/veggieProcessor.fs.glsl"), GL_FRAGMENT_SHADER, log);
		effect = new Effect(moxane, typeof(this).stringof);
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

	~this() @trusted
	{
		destroy(textureArray);
		destroy(effect);
		glDeleteVertexArrays(1, &vao);
	}

	override void finaliseResources() @trusted
	{
		foreach(MeshID i; 0 .. registry.meshCount)
		{
			auto vm = cast(IVegetationVoxelMesh)registry.getMesh(i);
			if(vm is null) continue;
			meshes[i] = vm;
		}
		meshes.rehash;

		auto textureFiles = new string[](textures.length);
		foreach(x, texture; textures) 
		{
			texture.id = cast(ubyte)x;
			textureFiles[x] = texture.file;
		}
		textureArray = new Texture2DArray(textureFiles, true, Filter.nearest, Filter.nearest, true);

		foreach(MaterialID i; 0 .. registry.materialCount)
		{
			auto vm = cast(IVegetationVoxelMaterial)registry.getMaterial(i);
			if(vm is null) continue;
			vm.loadTextures(this);
			materials[i] = vm;
		}
		materials.rehash;

		import std.stdio;
		writeln("Meshes: ", meshes);
		writeln("Materials: ", materials);
	}

	override void removeChunk(IMeshableVoxelBuffer meshableVoxelBuffer) @trusted
	{
		auto renderableVoxelBuffer = cast(IRenderableVoxelBuffer)meshableVoxelBuffer;
		if(meshableVoxelBuffer is null) return;
		if(isRenderDataNull(renderableVoxelBuffer)) return;
		RenderData* rd = getRenderData(renderableVoxelBuffer);
		rd.destroy;
		renderDataPool.give(rd);
		renderableVoxelBuffer.drawData[id_] = null;
	}

	override void updateFromManager() { }

	private bool isRenderDataNull(IRenderableVoxelBuffer vb) { return vb.drawData[id_] is null; }
	private RenderData* getRenderData(IRenderableVoxelBuffer vb) @trusted { return cast(RenderData*)vb.drawData[id_]; }

	private void uploadChunk(ref MeshResult result) @trusted
	{
		auto chunk = cast(IRenderableVoxelBuffer)result.order.chunk;
		assert(chunk !is null);
		bool hasRD = !isRenderDataNull(chunk);

		if(result.buffer is null)
		{
			if(hasRD)
				removeChunk(result.order.chunk);
			result.order.chunk.meshBlocking(false, id_);
			return;
		}

		RenderData* rd;
		if(hasRD)
			rd = getRenderData(chunk);
		else
		{
			rd = renderDataPool.get;
			rd.create;
			chunk.drawData[id_] = cast(void*)rd;
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

	private void performUploads() @trusted
	{
		StopWatch uploadSW = StopWatch(AutoStart.yes);
		while(uploadSW.peek.total!"msecs" < 4 && !meshResults.empty)
		{
			Maybe!MeshResult meshResult = meshResults.tryGet;
			if(meshResult.isNull) return;

			uploadChunk(*meshResult.unwrap());	
		}
	}

	void drawChunk(IMeshableVoxelBuffer meshable, ref LocalContext context, ref PipelineStatics stats) @trusted
	{
		//if(context.state != PipelineDrawState.scene) return;

		auto chunk = cast(IRenderableVoxelBuffer)meshable;

		RenderData* rd = getRenderData(chunk);
		if(rd is null) return;

		Matrix4f m = translationMatrix(chunk.transform.position);
		Matrix4f nm = /*lc.model **/ m;
		Matrix4f mvp = context.camera.projection * context.camera.viewMatrix * nm;
		Matrix4f mv = context.camera.viewMatrix * nm;

		effect["ModelViewProjection"].set(&mvp);
		effect["Model"].set(&nm);
		effect["ModelView"].set(&mv);

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
		stats.vertexCount += rd.vertexCount;
		stats.drawCalls++;
	}
	
	void beginDraw(Pipeline pipeline, ref LocalContext context) @trusted
	{
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

	void endDraw(Pipeline pipeline, ref LocalContext context) @trusted
	{
		foreach(x; 0 .. 3)
			glDisableVertexAttribArray(x);
		effect.unbind;
		glBindVertexArray(0);
	}

	override IVegetationVoxelTexture getTexture(ushort id) { return textures[id]; }
	override IVegetationVoxelTexture getTexture(string technical) { return textures.find!(a => a.technical == technical)[0]; }
	override IVegetationVoxelMesh getMesh(MeshID id) { auto ptr = id in meshes; if(ptr is null) return null; else return *ptr; }
	override IVegetationVoxelMaterial getMaterial(MaterialID id) { auto ptr = id in materials; if(ptr is null) return null; else return *ptr; }
}