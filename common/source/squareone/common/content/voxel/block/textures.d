module squareone.common.content.voxel.block.textures;

import squareone.common.content.voxel.block.types;
import squareone.common.content.voxel.block.processor;
import squareone.common.voxel;
import squareone.common.meta;

import moxane.core : AssetManager;

import std.file;
import std.path;

@safe:

template TextureImpl(string technical, string display, string filename)
{
	const char[] TextureImpl = "static immutable string technicalStatic = \"" ~ technical  ~"\";
		mixin(VoxelContentQuick!(technicalStatic, \"" ~ display ~ "\", name, dylanGraham));

		private ushort id_;
		@property ushort id() { return id_; }
		@property void id(ushort v) { id_ = v; }

		@property string file() { return AssetManager.translateToAbsoluteDir(\"content/textures/" ~ filename ~ "\"); }";
}

final class DirtTexture : IBlockVoxelTexture 
{
	static immutable string technicalStatic = "squareOne:voxel:blockTexture:dirt";
	mixin(VoxelContentQuick!(technicalStatic, "Dirt (texture)", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort v) { id_ = v; }

	@property string file() { return AssetManager.translateToAbsoluteDir("content/textures/dirt.png"); }
}

final class GrassTexture : IBlockVoxelTexture 
{
	static immutable string technicalStatic = "squareOne:voxel:blockTexture:grass";
	mixin(VoxelContentQuick!(technicalStatic, "Grass (texture)", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort v) { id_ = v; }

	@property string file() { return AssetManager.translateToAbsoluteDir("content/textures/grass.png"); }
}

final class SandTexture : IBlockVoxelTexture
{
	static immutable string technicalStatic = "squareone:voxel:blockTexture:sand";
	mixin(VoxelContentQuick!(technicalStatic, "Sand (texture)", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort v) { id_ = v; }

	@property string file() { return AssetManager.translateToAbsoluteDir("content/textures/sand.png"); }
}

final class StoneTexture : IBlockVoxelTexture
{
	mixin(TextureImpl!("squareone:voxel:blockTexture:stone", "Stone (texture)", "stone.png"));
}

final class GlassTexture : IBlockVoxelTexture
{
	mixin(TextureImpl!("squareOne:voxel:blockTexture:glass", "Glass (texture)", "glassDebug.png"));
}

final class WoodBarkTexture : IBlockVoxelTexture
{
	mixin(TextureImpl!("squareOne:voxel:blockTexture:woodBark", "Wood Bark (texture)", "woodBark.png"));
}

final class WoodCoreTexture : IBlockVoxelTexture
{
	mixin(TextureImpl!("squareOne:voxel:blockTexture:woodCore", "Wood Core (texture)", "woodCore.png"));
}
