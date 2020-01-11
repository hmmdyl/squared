module squareone.content.voxel.block.meshes.invisible;

import squareone.content.voxel.block.processor;
import squareone.content.voxel.block.types;
import squareone.voxel;
import squareone.util.spec;

import dlib.math;

final class Invisible : IBlockVoxelMesh 
{
	static immutable string technicalStatic = "squareOne:voxel:blockMesh:invisible";
	mixin(VoxelContentQuick!(technicalStatic, "invisible", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	SideSolidTable isSideSolid(Voxel voxel, VoxelSide side) { return SideSolidTable.notSolid; }

	void finalise(BlockProcessor bp) {}

	void generateMesh(Voxel target, int voxelSkip, ref Voxel[6] neighbours, ref SideSolidTable[6] sidesSolid, Vector3i coord, ref Vector3f[64] verts, ref Vector3f[64] normals, out int vertCount) 
	{ vertCount = 0; }
}