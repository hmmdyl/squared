module squareone.voxelcontent.block.types;

import squareone.voxel;
import squareone.voxelcontent.block.processor;

import dlib.math.vector;

interface IBlockVoxelMesh  : IVoxelMesh 
{
	void finalise(BlockProcessor bp);
	void generateMesh(Voxel target, int voxelSkip, ref Voxel[6] neigbours, ref SideSolidTable[6] sidesSolid, Vector3i coord, ref Vector3f[64] verts, ref Vector3f[64] normals, out int vertCount);
}

interface IBlockVoxelMaterial : IVoxelMaterial 
{
	void loadTextures(scope BlockProcessor bp);
	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] textureIDs);
}

interface IBlockVoxelTexture : IVoxelContent 
{
	@property ushort id();
	@property void id(ushort);

	@property string file();
}

struct RenderData
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