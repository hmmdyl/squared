module square.one.voxelcon.block.textures.grasstexture;

import square.one.voxelcon.block.processor;

import std.file;
import std.path;

final class GrassTexture : IBlockVoxelTexture {
	static immutable string technicalStatic = "block_texture_grass";

	mixin(VoxelContentQuick!(technicalStatic, "Grass (texture)", squareOneMod, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort v) { id_ = v; }

	private static string grassTextureFile;
	@property string file() { 
		if(grassTextureFile is null)
			grassTextureFile = buildPath(getcwd(), "assets/textures/grass.png");
		return grassTextureFile; 
	}
}