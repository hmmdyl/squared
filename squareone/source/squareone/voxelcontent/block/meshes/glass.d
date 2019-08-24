module squareone.voxelcontent.block.meshes.glass;

import squareone.voxelcontent.block.processor;
import squareone.voxelcontent.block.types;
import squareone.voxel;
import squareone.util.spec;

import dlib.math.vector;

/+final class GlassMesh : IBlockVoxelMesh
{
	static immutable string technicalStatic = "squareOne:voxel:blockMesh:glass";
	mixin(VoxelContentQuick!(technicalStatic, "Glass", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	SideSolidTable isSideSolid(Voxel voxel, VoxelSide side) { return SideSolidTable.notSolid; }

	BlockProcessor bp;
	void finalise(BlockProcessor bp)
	{
		this.bp = bp;
	}

	void generateMesh(Voxel target, int voxelSkip, ref Voxel[6] neighbours, ref SideSolidTable[6] sidesSolid, Vector3i coord, ref Vector3f[64] verts, ref Vector3f[64] normals, out int vertCount)
	{
		SideSolidTable[6] correctTable;
		foreach(size_t i, ref SideSolidTable sst; correctTable)
			sst = neighbours[i].mesh == target.mesh ? SideSolidTable.solid : sidesSolid[i];
		
		MeshID trueMeshID = target.materialData & 0xFFF;
		Voxel blankedTarget = target;
		blankedTarget.materialData = target.materialData & ~0xFFF;
		bp.getMesh(1).generateMesh(blankedTarget, voxelSkip, neighbours, correctTable, coord, verts, normals, vertCount);
	}
}+/