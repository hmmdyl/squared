module squareone.voxelcontent.vegetation.materials;

import squareone.voxel;
import squareone.voxelcontent.vegetation.meshes;
import squareone.voxelcontent.vegetation.types;
import squareone.voxelcontent.vegetation.processor;
import moxane.core;
import squareone.util.spec;

final class GrassBlade : IVegetationVoxelMaterial
{
	static immutable string technicalStatic = "squareOne:voxel:vegetationMaterial:grass";
	mixin(VoxelContentQuick!(technicalStatic, "Grass", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort c) { id_ = c; }

	void loadTextures(VegetationProcessor proc)
	{
		grassTextureID = proc.textureID(GrassBladeTexture.technicalStatic);
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
	mixin(VoxelContentQuick!(technicalStatic, "Grass", appName, dylanGrahamName));

	private ubyte id_;
	@property ubyte id() const { return id_; }
	@property void id(ubyte c) { id_ = c; }

	@property string file() { return AssetManager.translateToAbsoluteDir("content/textures/grass_blades_shitty.png"); }
}