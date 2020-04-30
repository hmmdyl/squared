module squareone.common.content.voxel.block.meshes.horizslope;

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

immutable ushort[3][2][5][4] slopeIndices = [
	[	// ROTATION 0
		[[0, 2, 4], [6, 4, 2]],	// -X
		[[2, 0, 3]],			// -Y
		[[4, 6, 7]],			// +Y
		[[2, 3, 6], [7, 6, 3]],	// +Z
		[[3, 0, 7],	[4, 7, 0]]	// diag
	],
	[	// ROTATION 1
		[[0, 2, 4], [6, 4, 2]],	// -X
		[[0, 1, 2]],			// -Y
		[[4, 6, 5]],			// +Y
		[[1, 0, 5], [4, 5, 0]],	// -Z
		[[2, 1, 6], [5, 6, 1]]	// diag
	],
	[	// ROTATION 2
		[[1, 5, 3], [7, 3, 5]],	// +X
		[[1, 3, 0]],			// -Y
		[[7, 5, 4]],			// +Y
		[[0, 4, 1], [5, 1, 4]],	// -Z
		[[3, 7, 0], [4, 0, 7]]	// diag
	],
	[	// ROTATION 3
		[[3, 1, 7], [5, 7, 1]],	// +X
		[[2, 1, 3]],			// -Y
		[[5, 6, 7]],			// +Y
		[[3, 7, 2], [6, 2, 7]],	// +Z
		[[5, 1, 2], [2, 6, 5]]	// diag
	]
	];

immutable Vector3f[5][4] slopeNormals = [
	[ // ROTATION 0
	  Vector3f(-1f, 0f, 0f),
	  Vector3f(0f, -1f, 0f),
	  Vector3f(0f, 1f, 0f),
	  Vector3f(0f, 0f, 1f),
	  Vector3f(0.5f, 0f, -0.5f)
	],
	[ // ROTATION 1
	  Vector3f(-1f, 0f, 0f),
	  Vector3f(0f, -1f, 0f),
	  Vector3f(0f, 1f, 0f),
	  Vector3f(0f, 0f, -1f),
	  Vector3f(0.5f, 0f, 0.5f)
	],
	[ // ROTATION 2
	  Vector3f(1f, 0f, 0f),
	  Vector3f(0f, -1f, 0f),
	  Vector3f(0f, 1f, 0f),
	  Vector3f(0f, 0f, -1f),
	  Vector3f(-0.5f, 0f, 0.5f)
	],
	[ // ROTATION 3
	  Vector3f(1f, 0f, 0f),
	  Vector3f(0f, -1f, 0f),
	  Vector3f(0f, 1f, 0f),
	  Vector3f(0f, 0f, 1f),
	  Vector3f(-0.5f, 0f, -0.5f)
	]
	];

alias SST = SideSolidTable;

final class HorizontalSlope : IBlockVoxelMesh {
	static immutable string technicalStatic = "squareOne:voxel:blockMesh:horizontalSlope";
	mixin(VoxelContentQuick!(technicalStatic, "Horizontal slope", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	SideSolidTable isSideSolid(Voxel voxel, VoxelSide side) {
		return SST.notSolid;
	}

	void finalise(BlockProcessorBase bp) {}

	void generateMesh(Voxel target, int voxelSkip, ref Voxel[6] neighbours, ref SideSolidTable[6] sidesSolid, Vector3i coord, ref Vector3f[64] verts, ref Vector3f[64] normals, out int vertCount) {
		int v = 0, n = 0;

		ubyte rotation = target.meshData & 7;

		void addTriag(ushort[3] indices, int dir) {
			foreach(i; 0 .. 3) {
				verts[v++] = cubeVertices[indices[i]] * voxelSkip + Vector3f(coord);
				normals[n++ ] = slopeNormals[rotation][dir];
			}
		}

		bool allAreSolid = sidesSolid[VoxelSide.nx] == SST.solid && 
			sidesSolid[VoxelSide.px] == SST.solid && 
			sidesSolid[VoxelSide.ny] == SST.solid && 
			sidesSolid[VoxelSide.py] == SST.solid && 
			sidesSolid[VoxelSide.nz] == SST.solid && 
			sidesSolid[VoxelSide.pz] == SST.solid;

		final switch(rotation) {
			case 0:
				addTriag(slopeIndices[0][0][0], 0);
				addTriag(slopeIndices[0][0][1], 0);
				addTriag(slopeIndices[0][1][0], 1);
				addTriag(slopeIndices[0][2][0], 2);
				addTriag(slopeIndices[0][3][0], 3);
				addTriag(slopeIndices[0][3][1], 3);
				addTriag(slopeIndices[0][4][0], 4);
				addTriag(slopeIndices[0][4][1], 4);
				break;
			case 1:
				addTriag(slopeIndices[1][0][0], 0);
				addTriag(slopeIndices[1][0][1], 0);
				addTriag(slopeIndices[1][1][0], 1);
				addTriag(slopeIndices[1][2][0], 2);
				addTriag(slopeIndices[1][3][0], 3);
				addTriag(slopeIndices[1][3][1], 3);
				addTriag(slopeIndices[1][4][0], 4);
				addTriag(slopeIndices[1][4][1], 4);
				break;
			case 2:
				addTriag(slopeIndices[2][0][0], 0);
				addTriag(slopeIndices[2][0][1], 0);
				addTriag(slopeIndices[2][1][0], 1);
				addTriag(slopeIndices[2][2][0], 2);
				addTriag(slopeIndices[2][3][0], 3);
				addTriag(slopeIndices[2][3][1], 3);
				addTriag(slopeIndices[2][4][0], 4);
				addTriag(slopeIndices[2][4][1], 4);
				break;
			case 3:
				addTriag(slopeIndices[3][0][0], 0);
				addTriag(slopeIndices[3][0][1], 0);
				addTriag(slopeIndices[3][1][0], 1);
				addTriag(slopeIndices[3][2][0], 2);
				addTriag(slopeIndices[3][3][0], 3);
				addTriag(slopeIndices[3][3][1], 3);
				addTriag(slopeIndices[3][4][0], 4);
				addTriag(slopeIndices[3][4][1], 4);
				break;
		}

		vertCount = v;
	}
}