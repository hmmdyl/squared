module squareone.client.content.voxel.block.processor;

import squareone.client.voxel;
import squareone.common.content.voxel.block;
import squareone.common.voxel;

import moxane.core;
import moxane.graphics.redo;
import moxane.utils.pool;
import moxane.physics;

import derelict.opengl3.gl3;
import dlib.math;

@safe:

final class BlockProcessor : BlockProcessorBase, IClientProcessor
{
	private Pool!(RenderData*) renderDataPool;

	private uint vao;
	private Effect effect;

	private IBlockVoxelMesh[int] meshes;
	IBlockVoxelTexture[] textures;
	private Texture2DArray textureArray;

	PhysicsSystem physics;

	this(Moxane moxane, VoxelRegistry registry, IBlockVoxelTexture[] textures) @trusted
	in { assert(moxane !is null); assert(textures !is null); assert(textures.length > 0); }
	do {
		this.moxane = moxane;
		this.registry = registry;
		this.textures = textures;

		foreach(id, IBlockVoxelTexture t; this.textures) t.id = cast(ushort)id;

		meshBufferHost = new MeshBufferHost;
		uploadSyncObj = new Object;
		renderDataPool = Pool!(RenderData*)(() => new RenderData(), 64);

		glGenVertexArrays(1, &vao);

		Log log = moxane.services.getAOrB!(GraphicsLog, Log);
		Shader vs, fs;
		vs = new Shader(AssetManager.translateToAbsoluteDir("content/shaders/blockProcessor.vs.glsl"), GL_VERTEX_SHADER, log);
		fs = new Shader(AssetManager.translateToAbsoluteDir("content/shaders/blockProcessor.fs.glsl"), GL_FRAGMENT_SHADER, log);
		effect = new Effect(moxane, BlockProcessor.stringof);
		effect.attachAndLink(vs, fs);
		effect.bind();
		effect.findUniform("ModelViewProjection");
		effect.findUniform("Fit10bScale");
		effect.findUniform("Diffuse");
		effect.findUniform("Model");
		effect.findUniform("ModelView");
		effect.unbind();
	}

	override void finaliseResources() @trusted
	{
		foreach(i; 0 .. registry.meshCount)
		{
			auto bm = cast(IBlockVoxelMesh)registry.getMesh(i);
			if(bm is null) continue;
			meshes[i] = bm;
		}
		meshes.rehash;

		foreach(bm; meshes.values) bm.finalise(this);

		auto textureFiles = new string[](textures.length);
		foreach(x, texture; textures) textureFiles[x] = texture.file;
		textureArray = new Texture2DArray(textureFiles, true, Filter.nearest, Filter.nearest, true);

		foreach(i; 0 .. registry.materialCount)
		{
			auto bm = cast(IBlockVoxelMaterial)registry.getMaterial(i);
			if(bm is null) continue;
			bm.loadTextures(this);
		}
	}

	private bool isRenderDataNull(IRenderableVoxelBuffer vb) { return vb.drawData[id_] is null; }
	private RenderData* getRenderData(IRenderableVoxelBuffer vb) @trusted { return cast(RenderData*)vb.drawData[id_]; }

	override void removeChunk(IMeshableVoxelBuffer vb) 
	{
		auto voxelBuffer = cast(IRenderableVoxelBuffer)vb;
		if(isRenderDataNull(voxelBuffer)) return;
		RenderData* rd = getRenderData(voxelBuffer);
		rd.destroy;
		renderDataPool.give(rd);
		voxelBuffer.drawData[id_] = null;
	}

	override void updateFromManager() {}

	private uint uploadCount = 0;

	private void uploadChunk(ref MeshResult result) @trusted
	{
		IRenderableVoxelBuffer chunk = cast(IRenderableVoxelBuffer)result.order.chunk;
		assert(chunk !is null);
		bool hasRD = !isRenderDataNull(chunk);

		if(result.buffer is null)
		{
			result.order.chunk.meshBlocking(false, id_);
			if(!isRenderDataNull(chunk))
			{
				RenderData* rd = getRenderData(chunk);
				rd.destroy;
				if(rd.collider !is null)
				{
					destroy(rd.collider);
					destroy(rd.rigidBody);
				}
				chunk.drawData[id_] = null;
			}
			return;
		}

		RenderData* rd;
		if(hasRD)
			rd = getRenderData(chunk);
		else {
			rd = renderDataPool.get();
			rd.create();
			chunk.drawData[id_] = cast(void*)rd;
		}

		rd.collider = new StaticMeshCollider(physics, result.buffer.vertices[0..result.buffer.vertexCount], true, false);
		rd.rigidBody = new BodyMT(physics, BodyMT.Mode.dynamic, rd.collider, (chunk.transform));
		rd.rigidBody.collidable = true;

		rd.vertexCount = result.buffer.vertexCount;

		rd.chunkMax = result.buffer.chunkMax;
		rd.fit10BitScale = result.buffer.fit10Bit;

		glBindBuffer(GL_ARRAY_BUFFER, rd.vertexBO);
		glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, result.buffer.compressedVertices.ptr, GL_STATIC_DRAW);
		glBindBuffer(GL_ARRAY_BUFFER, rd.normalBO);
		glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, result.buffer.compressedNormals.ptr, GL_STATIC_DRAW);

		glBindBuffer(GL_ARRAY_BUFFER, rd.metaBO);
		glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, result.buffer.meta.ptr, GL_STATIC_DRAW);
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		result.order.chunk.meshBlocking(false, id_);

		result.buffer.reset;
		meshBufferHost.give(result.buffer);

		uploadCount++;
	}

	private void performUploads()
	{
		bool isEmpty() {
			synchronized(uploadSyncObj) {
				return uploadQueue.empty;
			}
		}

		MeshResult getFromUploadQueue() {
			synchronized(uploadSyncObj) {
				if(uploadQueue.empty) throw new Exception("die");
				MeshResult i = uploadQueue.front;
				uploadQueue.removeFront();
				return i;
			}
		}

		while(!isEmpty)
		{
			MeshResult uploadItem = getFromUploadQueue;
			
			uploadChunk(uploadItem);
		}
	}

	void drawChunk(IMeshableVoxelBuffer meshable, ref LocalContext context, ref PipelineStatics stats) @trusted
	{
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

		effect["Fit10bScale"].set(rd.fit10BitScale);

		import derelict.opengl3.gl3;
		glBindBuffer(GL_ARRAY_BUFFER, rd.vertexBO);
		glVertexAttribPointer(0, 4, GL_UNSIGNED_INT_2_10_10_10_REV, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, rd.normalBO);
		glVertexAttribPointer(1, 4, GL_UNSIGNED_INT_2_10_10_10_REV, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, rd.metaBO);
		glVertexAttribIPointer(2, 4, GL_UNSIGNED_BYTE, 0, null);
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

		glActiveTexture(GL_TEXTURE0);
		textureArray.bind;
		effect["Diffuse"].set(0);
	}

	void endDraw(Pipeline pipeline, ref LocalContext context) @trusted
	{
		foreach(x; 0 .. 3)
			glDisableVertexAttribArray(x);

		textureArray.unbind;
		effect.unbind;

		glBindVertexArray(0);
	}

	override IBlockVoxelTexture getTexture(ushort id) { return textures[id]; }
	override IBlockVoxelTexture getTexture(string technical)
	{
		import std.algorithm.searching : find;
		return textures.find!(a => a.technical == technical)[0];
	}

	override IBlockVoxelMesh getMesh(MeshID id) { return meshes[id]; }
}

private struct RenderData
{
	uint[3] buffers;
	@property uint vertexBO() const { return buffers[0]; }
	@property uint normalBO() const { return buffers[1]; }
	@property uint metaBO() const { return buffers[2]; }

	int vertexCount;

	float chunkMax, fit10BitScale;

	BodyMT rigidBody;
	Collider collider;

	void create() @trusted
	{
		import derelict.opengl3.gl3 : glGenBuffers;
		glGenBuffers(1, &buffers[0]);
		glGenBuffers(1, &buffers[1]);
		glGenBuffers(1, &buffers[2]);
		vertexCount = 0;
	}

	void destroy() @trusted
	{
		import derelict.opengl3.gl3 : glDeleteBuffers;
		glDeleteBuffers(3, buffers.ptr);
		vertexCount = 0;
	}
}