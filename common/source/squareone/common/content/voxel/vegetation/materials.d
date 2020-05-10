module squareone.common.content.voxel.vegetation.materials;

import squareone.common.voxel;
import squareone.common.content.voxel.vegetation.types;
import squareone.common.content.voxel.vegetation.processor;
import squareone.common.meta;
import moxane.core;

final class GrassBlade : IVegetationVoxelMaterial
{
	static immutable string technicalStatic = "squareOne:voxel:vegetationMaterial:grass";
	mixin(VoxelContentQuick!(technicalStatic, "Grass", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort c) { id_ = c; }

	void loadTextures(VegetationProcessorBase proc)
	{
		grassTextureID = proc.getTexture(GrassBladeTexture.technicalStatic).id;
	}

	private ubyte grassTextureID;

	@property ubyte grassTexture() const { return grassTextureID; }
	@property ubyte flowerStorkTexture() const { return 0; }
	@property ubyte flowerHeadTexture() const { return 0; }
	@property ubyte flowerLeafTexture() const { return 0; }
}

final class GrassBladeTexture : IVegetationVoxelTexture
{
	static immutable string technicalStatic = "squareOne:voxel:vegetationTexture:grassTexture";
	mixin(VoxelContentQuick!(technicalStatic, "Grass", name, dylanGraham));

	private ubyte id_;
	@property ubyte id() const { return id_; }
	@property void id(ubyte c) { id_ = c; }

	@property string file() { return AssetManager.translateToAbsoluteDir("content/textures/grassBlades4.png"); }
}
