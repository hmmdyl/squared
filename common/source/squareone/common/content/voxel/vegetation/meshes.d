module squareone.common.content.voxel.vegetation.meshes;

import squareone.common.content.voxel.vegetation.types;
import squareone.common.content.voxel.vegetation.processor;
import squareone.common.voxel;
import squareone.common.meta;

final class GrassMesh : IVegetationVoxelMesh
{
	static immutable string technicalStatic = "squareOne:voxel:vegetationMesh:grass";
	mixin(VoxelContentQuick!(technicalStatic, "Grass", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	SideSolidTable isSideSolid(Voxel v, VoxelSide side) { return SideSolidTable.notSolid; }

	@property MeshType meshType() const { return MeshType.grass; }

	void generateOtherMesh() {}
}

final class LeafMesh : IVegetationVoxelMesh
{
	static immutable string technicalStatic = "squareOne:voxel:vegetationMesh:leaf";
	mixin(VoxelContentQuick!(technicalStatic, "Leaf", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	SideSolidTable isSideSolid(Voxel v, VoxelSide side) { return SideSolidTable.notSolid; }

	@property MeshType meshType() const { return MeshType.leaf; }

	void generateOtherMesh() {}
}