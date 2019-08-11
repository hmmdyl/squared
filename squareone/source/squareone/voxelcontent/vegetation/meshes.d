module squareone.voxelcontent.vegetation.meshes;

import squareone.voxelcontent.vegetation.types;
import squareone.voxel;
import squareone.voxelcontent.vegetation.processor;
import squareone.util.spec;

final class GrassMesh : IVegetationVoxelMesh
{
	static immutable string technicalStatic = "squareOne:voxel:vegetationMesh:grass";
	mixin(VoxelContentQuick!(technicalStatic, "Grass", appName, dylanGrahamName));

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
	mixin(VoxelContentQuick!(technicalStatic, "Leaf", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	SideSolidTable isSideSolid(Voxel v, VoxelSide side) { return SideSolidTable.notSolid; }

	@property MeshType meshType() const { return MeshType.leaf; }

	void generateOtherMesh() {}
}