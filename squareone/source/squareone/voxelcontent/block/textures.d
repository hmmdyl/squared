module squareone.voxelcontent.block.textures;

import squareone.voxelcontent.block.processor;
import squareone.voxelcontent.block.types;
import squareone.util.spec;
import squareone.voxel;

import moxane.core : AssetManager;

import std.file;
import std.path;

final class DirtTexture : IBlockVoxelTexture 
{
	static immutable string technicalStatic = "squareOne:voxel:blockTexture:dirt";
	mixin(VoxelContentQuick!(technicalStatic, "Dirt (texture)", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort v) { id_ = v; }

	@property string file() { return AssetManager.translateToAbsoluteDir("content/textures/stone.png"); }
}

final class GrassTexture : IBlockVoxelTexture 
{
	static immutable string technicalStatic = "squareOne:voxel:blockTexture:grass";
	mixin(VoxelContentQuick!(technicalStatic, "Grass (texture)", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort v) { id_ = v; }

	@property string file() { return AssetManager.translateToAbsoluteDir("content/textures/stone.png"); }
}