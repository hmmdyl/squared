module square.one.voxelcon.block.materials.air;

import square.one.voxelcon.block.processor;

final class Air : IBlockVoxelMaterial {
	@property string technical() { return "block_material_air"; }
	@property string display() { return "Air"; }
	@property string mod() { return squareOneMod; }
	@property string author() { return dylanGrahamName; }
	
	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	void loadTextures(scope BlockProcessor bp) {

	}

	void generateTextureIDs(int vlength, ref vec3f[64] vertices, ref vec3f[64] normals, ref ushort[64] ids) {
		ids[] = 0;
	}
}