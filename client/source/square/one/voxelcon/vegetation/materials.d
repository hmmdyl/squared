module square.one.voxelcon.vegetation.materials;

import square.one.terrain.resources;
import square.one.voxelcon.vegetation.processor;

import std.file;
import std.path;

final class FlowerMediumTest : IVegetationVoxelMaterial {
	static immutable string technicalStatic = "vegetation_flower_medium_test";
	mixin(VoxelContentQuick!(technicalStatic, "Flower medium (TEST)", squareOneMod, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	private ubyte storkTextureID;
	private ubyte headTextureID;

	void loadTextures(VegetationProcessor vp) {
		headTextureID = vp.getTextureID(FlowerMediumTestHeadTexture.technicalStatic);
		storkTextureID =vp.getTextureID(FlowerMediumTestStorkTexture.technicalStatic);
	}

	@property ubyte grassTexture() const { return storkTextureID; }
	@property ubyte flowerStorkTexture() const { return storkTextureID; }
	@property ubyte flowerHeadTexture() const { return headTextureID; }

	void applyTexturesOther() {}
}

final class FlowerMediumTestHeadTexture : IVegetationVoxelTexture {
	static immutable string technicalStatic = "vegetation_flower_medium_test_head_texture";
	mixin(VoxelContentQuick!(technicalStatic, "Flower medium (TEST)", squareOneMod, dylanGrahamName));

	private ubyte id_;
	@property ubyte id() { return id_; }
	@property void id(ubyte nid) { id_ = nid; }

	@property string file() {
		return buildPath(getcwd(), "assets/textures/flower_texture.png");
	}
}

final class FlowerMediumTestStorkTexture : IVegetationVoxelTexture {
	static immutable string technicalStatic = "vegetation_flower_medium_test_stork_texture";
	mixin(VoxelContentQuick!(technicalStatic, "Flower medium (TEST)", squareOneMod, dylanGrahamName));

	private ubyte id_;
	@property ubyte id() { return id_; }
	@property void id(ubyte nid) { id_ = nid; }

	@property string file() {
		return buildPath(getcwd(), "assets/textures/grass_blades_shitty.png");
	}
}