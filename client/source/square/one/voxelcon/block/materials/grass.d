module square.one.voxelcon.block.materials.grass;

import square.one.voxelcon.block.processor;
import square.one.voxelcon.block.textures;
import dlib.math;

final class Grass : IBlockVoxelMaterial {
	static immutable string technicalStatic = "block_material_grass";
	mixin(VoxelContentQuick!(technicalStatic, "Grass", squareOneMod, dylanGrahamName));
	
	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }
	
	ushort dirtTextureID;
	ushort grassTextureID;

	void loadTextures(scope BlockProcessor bp) {
		dirtTextureID = bp.getTexture(DirtTexture.technicalStatic).id;
		grassTextureID = bp.getTexture(GrassTexture.technicalStatic).id;
	}
	
	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] ids) {
		for(int x = 0; x < vlength; x += 3) {
			if(normals[x].y >= 0f) {
				ids[x] = grassTextureID;
				ids[x + 1] = grassTextureID;
				ids[x + 2] = grassTextureID;
			}
			else {
				ids[x] = dirtTextureID;
				ids[x + 1] = dirtTextureID;
				ids[x + 2] = dirtTextureID;
			}
		}
	}
}