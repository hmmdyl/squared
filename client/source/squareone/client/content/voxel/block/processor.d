module squareone.client.content.voxel.block.processor;

import squareone.client.voxel;
import squareone.common.content.voxel.block;
import squareone.common.voxel;

import moxane.core;
import moxane.graphics.redo;
import moxane.utils.pool;

@safe:

final class BlockProcessor : BlockProcessorBase, IClientProcessor
{
	private Pool!(RenderData*) renderDataPool;

	private uint vao;
	private Effect effect;

	private IBlockVoxelMesh[int] meshes;
	IBlockVoxelTexture[] textures;
	private Texture2DArray textureArray;

	this(Moxane moxane, IBlockVoxelTexture[] textures)
	in { assert(moxane !is null); assert(textures !is null); assert(textures.length > 0); }
	do {
		this.moxane = moxane;
		this.textures = textures;

		foreach(id, IBlockVoxelTexture t; this.textures) t.id = cast(ushort)id;

		meshBufferHost = new MeshBufferHost;
		uploadSyncObj = new Object;
		renderDataPool = Pool!(RenderData*)(() => new RenderData(), 64);
	}

	override void finaliseResources() 
	{
		this.meshBufferHost.give(null);
	}

	override void removeChunk(IMeshableVoxelBuffer voxelBuffer) {}
	override void updateFromManager() {}

	void beginDraw(Pipeline pipeline, ref LocalContext context) {}
	void drawChunk(IMeshableVoxelBuffer chunk, ref LocalContext context, ref PipelineStatics stats) {}
	void endDraw(Pipeline pipeline, ref LocalContext context) {}
}

private struct RenderData
{
	uint[3] buffers;
	@property uint vertexBO() const { return buffers[0]; }
	@property uint normalBO() const { return buffers[1]; }
	@property uint metaBO() const { return buffers[2]; }

	int vertexCount;

	float chunkMax, fit10BitScale;

	void create()
	{
		import derelict.opengl3.gl3 : glGenBuffers;
		glGenBuffers(1, &buffers[0]);
		glGenBuffers(1, &buffers[1]);
		glGenBuffers(1, &buffers[2]);
		vertexCount = 0;
	}

	void destroy()
	{
		import derelict.opengl3.gl3 : glDeleteBuffers;
		glDeleteBuffers(3, buffers.ptr);
		vertexCount = 0;
	}
}