module squareone.voxelcontent.block.materials;

import squareone.voxelcontent.block.processor;
import squareone.voxelcontent.block.types;
import squareone.voxel;
import squareone.util.spec;
import squareone.voxelcontent.block.textures;

import dlib.math;

template MaterialBasicImpl(string technical, string display, string textureTechnicalStatic, string author)
{
	const char[] MaterialBasicImpl = "static immutable string technicalStatic = \"" ~ technical ~ "\";
		mixin(VoxelContentQuick!(technicalStatic, \"" ~ display ~ "\", appName, \"" ~ author ~ "\"));

		private ushort id_;
		@property ushort id() { return id_; }
		@property void id(ushort nid) { id_ = nid; }

		ushort texID;

		void loadTextures(scope BlockProcessor bp) {
		texID = bp.getTexture(\"" ~ textureTechnicalStatic ~ "\").id;
		}

		void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
		{ ids[] = texID; }";
}

final class Air : IBlockVoxelMaterial 
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:air";
	mixin(VoxelContentQuick!(technicalStatic, "Air", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	void loadTextures(scope BlockProcessor bp) {}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{ ids[] = 0; }
}

final class Dirt : IBlockVoxelMaterial 
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:dirt";
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

final class Sand : IBlockVoxelMaterial
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:sand";
	mixin(VoxelContentQuick!(technicalStatic, "Sand", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	ushort sandTextureID;

	void loadTextures(scope BlockProcessor bp) {
		sandTextureID = bp.getTexture(SandTexture.technicalStatic).id;
	}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{ ids[] = sandTextureID; }
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

final class Stone : IBlockVoxelMaterial
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:stone";
	mixin(VoxelContentQuick!(technicalStatic, "Stone", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	ushort stoneTextureID;

	void loadTextures(scope BlockProcessor bp) {
		stoneTextureID = bp.getTexture(StoneTexture.technicalStatic).id;
	}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{ ids[] = stoneTextureID; }
}

final class WoodBark : IBlockVoxelMaterial
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:woodBark";
	mixin(VoxelContentQuick!(technicalStatic, "Treebark", appName, jamesGaywoodName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	ushort woodBarkTextureID;

	void loadTextures(scope BlockProcessor bp) {
		woodBarkTextureID = bp.getTexture(WoodBarkTexture.technicalStatic).id;
	}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{ ids[] = woodBarkTextureID; }
}

final class WoodCore : IBlockVoxelMaterial
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:woodCore";
	mixin(VoxelContentQuick!(technicalStatic, "Wood", appName, jamesGaywoodName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	ushort woodCoreTextureID;

	void loadTextures(scope BlockProcessor bp) {
		woodCoreTextureID = bp.getTexture(WoodCoreTexture.technicalStatic).id;
	}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{ ids[] = woodCoreTextureID; }
}

/+final class GlassMaterial : IBlockVoxelMaterial
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:glass";
	mixin(VoxelContentQuick!(technicalStatic, "Glass", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	ushort glassTextureID;

	void loadTextures(scope BlockProcessor bp) {
		glassTextureID = bp.getTexture(GlassTexture.technicalStatic).id;
	}

	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) 
	{ ids[] = glassTextureID; }
}+/