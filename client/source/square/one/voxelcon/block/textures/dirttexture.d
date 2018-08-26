module square.one.voxelcon.block.textures.dirttexture;

import square.one.voxelcon.block.processor;

import std.file;
import std.path;

final class DirtTexture : IBlockVoxelTexture {
	static immutable string technicalStatic = "block_texture_dirt";

	@property string technical() { return technicalStatic; }
	@property string display() { return "Dirt (texture)"; }
	@property string mod() { return squareOneMod; }
	@property string author() { return dylanGrahamName; }

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort v) { id_ = v; }

	private static string dirtTextureFile;
	@property string file() { 
		if(dirtTextureFile is null)
			dirtTextureFile = buildPath(getcwd(), "assets/textures/dirt.png");
		return dirtTextureFile; 
	}
}