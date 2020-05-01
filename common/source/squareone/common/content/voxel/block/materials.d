module squareone.common.content.voxel.block.materials;

import squareone.common.content.voxel.block.textures;
import squareone.common.content.voxel.block.types;
import squareone.common.content.voxel.block.processor;
import squareone.common.voxel;
import squareone.common.meta;

import dlib.math;

template MaterialBasicImpl(string technical, string display, string textureTechnicalStatic, string author)
{
	const char[] MaterialBasicImpl = "static immutable string technicalStatic = \"" ~ technical ~ "\";
		mixin(VoxelContentQuick!(technicalStatic, \"" ~ display ~ "\", name, \"" ~ author ~ "\"));

		private ushort id_;
		@property ushort id() { return id_; }
		@property void id(ushort nid) { id_ = nid; }

		ushort texID;

		void loadTextures(scope BlockProcessorBase bp) {
		texID = bp.getTexture(\"" ~ textureTechnicalStatic ~ "\").id;
		}

		void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
		{ ids[] = texID; }";
}

final class Air : IBlockVoxelMaterial 
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:air";
	mixin(VoxelContentQuick!(technicalStatic, "Air", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	void loadTextures(scope BlockProcessorBase bp) {}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{ ids[] = 0; }
}

final class Dirt : IBlockVoxelMaterial 
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:dirt";
	mixin(VoxelContentQuick!(technicalStatic, "Dirt", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	ushort dirtTextureID;

	void loadTextures(scope BlockProcessorBase bp) {
		dirtTextureID = bp.getTexture(DirtTexture.technicalStatic).id;
	}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{ ids[] = dirtTextureID; }
}

final class Sand : IBlockVoxelMaterial
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:sand";
	mixin(VoxelContentQuick!(technicalStatic, "Sand", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	ushort sandTextureID;

	void loadTextures(scope BlockProcessorBase bp) {
		sandTextureID = bp.getTexture(SandTexture.technicalStatic).id;
	}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{ ids[] = sandTextureID; }
}

final class Grass : IBlockVoxelMaterial 
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:grass";
	mixin(VoxelContentQuick!(technicalStatic, "Grass", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	ushort dirtTextureID;
	ushort grassTextureID;

	void loadTextures(scope BlockProcessorBase bp) 
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

final class Stone : IBlockVoxelMaterial
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:stone";
	mixin(VoxelContentQuick!(technicalStatic, "Stone", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	ushort stoneTextureID;

	void loadTextures(scope BlockProcessorBase bp) {
		stoneTextureID = bp.getTexture(StoneTexture.technicalStatic).id;
	}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{ ids[] = stoneTextureID; }
}

final class WoodBark : IBlockVoxelMaterial
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:woodBark";
	mixin(VoxelContentQuick!(technicalStatic, "Treebark", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	ushort woodBarkTextureID;

	void loadTextures(scope BlockProcessorBase bp) {
		woodBarkTextureID = bp.getTexture(WoodBarkTexture.technicalStatic).id;
	}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{ ids[] = woodBarkTextureID; }
}

final class WoodCore : IBlockVoxelMaterial
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:woodCore";
	mixin(VoxelContentQuick!(technicalStatic, "Wood", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	ushort woodCoreTextureID;

	void loadTextures(scope BlockProcessorBase bp) {
		woodCoreTextureID = bp.getTexture(WoodCoreTexture.technicalStatic).id;
	}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{ ids[] = woodCoreTextureID; }
}
