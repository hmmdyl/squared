module square.one.voxelcon.block.materials.dirt;

import square.one.voxelcon.block.processor;
import square.one.voxelcon.block.textures.dirttexture;

final class Dirt : IBlockVoxelMaterial {
	/*@property string technical() { return "block_material_dirt"; }
	@property string display() { return "Dirt"; }
	@property string mod() { return squareOneMod; }
	@property string author() { return dylanGrahamName; }*/

	static immutable string technicalStatic = "block_material_dirt";
	mixin(VoxelContentQuick!(technicalStatic, "Dirt", squareOneMod, dylanGrahamName));
	
	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	ushort dirtTextureID;

	void loadTextures(scope BlockProcessor bp) {
		dirtTextureID = bp.getTexture(DirtTexture.technicalStatic).id;
	}
	
	void generateTextureIDs(int vlength, ref vec3f[64] vertices, ref vec3f[64] normals, ref ushort[64] ids) {
		ids[] = dirtTextureID;
	}
}