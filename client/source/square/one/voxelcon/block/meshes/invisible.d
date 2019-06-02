module square.one.voxelcon.block.meshes.invisible;

import square.one.voxelcon.block.processor;
import dlib.math;

final class Invisible : IBlockVoxelMesh {
	@property string technical() { return "block_mesh_invisible"; }
	@property string display() { return "Invisible"; }
	@property string mod() { return squareOneMod; }
	@property string author() { return dylanGrahamName; }
	
	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }
	
	SideSolidTable isSideSolid(Voxel voxel, VoxelSide side) { return SideSolidTable.notSolid; }

	void generateMesh(Voxel target, int voxelSkip, ref Voxel[6] neighbours, ref SideSolidTable[6] sidesSolid, Vector3i coord, ref Vector3f[64] verts, ref Vector3f[64] normals, out int vertCount) {
		vertCount = 0;
	}
}