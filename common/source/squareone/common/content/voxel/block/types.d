module squareone.common.content.voxel.block.types;

import squareone.common.content.voxel.block.processor;
import squareone.common.voxel;

import dlib.math.vector : Vector3f, Vector3i;

@safe:

interface IBlockVoxelMesh : IVoxelMesh 
{
	void finalise(BlockProcessorBase bp);
	void generateMesh(Voxel target, int voxelSkip, ref Voxel[6] neigbours, ref SideSolidTable[6] sidesSolid, Vector3i coord, ref Vector3f[64] verts, ref Vector3f[64] normals, out int vertCount);
}

interface IBlockVoxelMaterial : IVoxelMaterial 
{
	void loadTextures(BlockProcessorBase bp);
	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] textureIDs);
}

interface IBlockVoxelTexture : IVoxelContent 
{
	@property ushort id();
	@property void id(ushort);

	@property string file();
}