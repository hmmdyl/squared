module squareone.client.content.voxel.vegetation.processor;

import squareone.client.voxel;
import squareone.common.content.voxel.vegetation;
import squareone.common.voxel;

import moxane.core;
import moxane.graphics.redo;
import moxane.utils.pool;

import derelict.opengl3.gl3;
import dlib.math;

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

	this(Moxane moxane, VoxelRegistry registry, IVegetationVoxelTexture[] textures)
	in { assert(moxane !is null); assert(registry !is null); assert(textures !is null); }
	do {
		super(moxane, registry);
		this.textures = textures;

		meshBufferPool = Pool!MeshBuffer(() @trusted => new MeshBuffer, 24, false);
		meshResults = new Channel!MeshResult;
		renderDataPool = Pool!(RenderData*)(() @trusted => new RenderData, 64);
	}

	~this()
	{
		destroy(textureArray);
		destroy(effect);
		glDeleteVertexArrays(1, &vao);
	}

	override void finaliseResources() 
	{
		
	}
}