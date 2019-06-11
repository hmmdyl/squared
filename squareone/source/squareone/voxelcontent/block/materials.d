module squareone.voxelcontent.block.materials;

import squareone.voxelcontent.block.processor;
import squareone.voxelcontent.block.types;
import squareone.voxel;
import squareone.util.spec;
import squareone.voxelcontent.block.textures;

import dlib.math;

final class Air : IBlockVoxelMaterial 
{
	mixin(VoxelContentQuick!("squareOne:voxel:blockMaterial:air", "Air", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	void loadTextures(scope BlockProcessor bp) {}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{ ids[] = 0; }
}

final class Dirt : IBlockVoxelMaterial 
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:air";
	mixin(VoxelContentQuick!(technicalStatic, "Dirt", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	ushort dirtTextureID;

	void loadTextures(scope BlockProcessor bp) {
		dirtTextureID = bp.getTexture(DirtTexture.technicalStatic).id;
	}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{ ids[] = dirtTextureID; }
}

final class Grass : IBlockVoxelMaterial 
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:grass";
	mixin(VoxelContentQuick!(technicalStatic, "Grass", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	ushort dirtTextureID;
	ushort grassTextureID;

	void loadTextures(scope BlockProcessor bp) 
	{
		dirtTextureID = bp.getTexture(DirtTexture.technicalStatic).id;
		grassTextureID = bp.getTexture(GrassTexture.technicalStatic).id;
	}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{
		for(int x = 0; x < vlength; x += 3) 
		{
			if(normals[x].y >= 0f) 
			{
				ids[x] = grassTextureID;
				ids[x + 1] = grassTextureID;
				ids[x + 2] = grassTextureID;
			}
			else 
			{
				ids[x] = dirtTextureID;
				ids[x + 1] = dirtTextureID;
				ids[x + 2] = dirtTextureID;
			}
		}
	}
}