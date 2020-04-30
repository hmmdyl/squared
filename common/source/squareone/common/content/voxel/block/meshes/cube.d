module squareone.common.content.voxel.block.meshes.cube;

import squareone.common.content.voxel.block.types;
import squareone.common.content.voxel.block.processor;
import squareone.common.voxel;
import squareone.common.meta;

import dlib.math;

@safe:

immutable Vector3f[8] cubeVertices = [
	Vector3f(0, 0, 0), // ind0
	Vector3f(1, 0, 0), // ind1
	Vector3f(0, 0, 1), // ind2
	Vector3f(1, 0, 1), // ind3
	Vector3f(0, 1, 0), // ind4
	Vector3f(1, 1, 0), // ind5
	Vector3f(0, 1, 1), // ind6
	Vector3f(1, 1, 1)  // ind7
];

immutable ushort[3][2][6] cubeIndices = [
	[[0, 2, 6], [6, 4, 0]], // -X
	[[7, 3, 1], [1, 5, 7]], // +X
	[[0, 1, 3], [3, 2, 0]], // -Y
	[[7, 5, 4], [4, 6, 7]], // +Y
	[[5, 1, 0], [0, 4, 5]], // -Z
	[[2, 3, 7], [7, 6, 2]]  // +Z
];

immutable Vector3f[6] cubeNormals = [
	Vector3f(-1, 0, 0),
	Vector3f(1, 0, 0),
	Vector3f(0, -1, 0),
	Vector3f(0, 1, 0),
	Vector3f(0, 0, -1),
	Vector3f(0, 0, 1)
];

final class Cube : IBlockVoxelMesh {
	static immutable string technicalStatic = "squareOne:voxel:blockMesh:cube";
	mixin(VoxelContentQuick!(technicalStatic, "Cube", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	SideSolidTable isSideSolid(Voxel voxel, VoxelSide side) { return SideSolidTable.solid; }

	void finalise(BlockProcessorBase bp) {}

	void generateMesh(Voxel target, int voxelSkip, ref Voxel[6] neighbours, ref SideSolidTable[6] sidesSolid, Vector3i coord, ref Vector3f[64] verts, ref Vector3f[64] normals, out int vertCount) {
		int v = 0, n = 0;

		void addTriag(ushort[3] indices, int dir) {
			Vector3f vfcoord = Vector3f(coord);
			verts[v++] = cubeVertices[indices[0]] * voxelSkip + vfcoord;
			verts[v++] = cubeVertices[indices[1]] * voxelSkip + vfcoord;
			verts[v++] = cubeVertices[indices[2]] * voxelSkip + vfcoord;

			normals[n++] = cubeNormals[dir];
			normals[n++] = cubeNormals[dir];
			normals[n++] = cubeNormals[dir];
		}

		void addSide(int dir) {
			addTriag(cubeIndices[dir][0], dir);
			addTriag(cubeIndices[dir][1], dir);
		}

		if(sidesSolid[VoxelSide.nx] != SideSolidTable.solid) addSide(VoxelSide.nx);
		if(sidesSolid[VoxelSide.px] != SideSolidTable.solid) addSide(VoxelSide.px);
		if(sidesSolid[VoxelSide.ny] != SideSolidTable.solid) addSide(VoxelSide.ny);
		if(sidesSolid[VoxelSide.py] != SideSolidTable.solid) addSide(VoxelSide.py);
		if(sidesSolid[VoxelSide.nz] != SideSolidTable.solid) addSide(VoxelSide.nz);
		if(sidesSolid[VoxelSide.pz] != SideSolidTable.solid) addSide(VoxelSide.pz);

		vertCount = v;
	}
}