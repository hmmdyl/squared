module square.one.voxelcon.vegetation.meshes;

import square.one.terrain.resources;
import square.one.voxelcon.vegetation.processor;

final class GrassMedium : IVegetationVoxelMesh {
	static immutable string technicalStatic = "vegetation_mesh_grass_medium";
	mixin(VoxelContentQuick!(technicalStatic, "Grass (medium)", squareOneMod, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	SideSolidTable isSideSolid(Voxel v, VoxelSide side) { return SideSolidTable.notSolid; }

	@property MeshType meshType() { return MeshType.grassMedium; }

	void generateOtherMesh() {}
}