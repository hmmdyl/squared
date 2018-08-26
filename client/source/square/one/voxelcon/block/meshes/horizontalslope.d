module square.one.voxelcon.block.meshes.horizontalslope;

import gfm.math;

import square.one.voxelcon.block.processor;

immutable vec3f[8] cubeVertices = [
	vec3f(0, 0, 0), // ind0
	vec3f(1, 0, 0), // ind1
	vec3f(0, 0, 1), // ind2
	vec3f(1, 0, 1), // ind3
	vec3f(0, 1, 0), // ind4
	vec3f(1, 1, 0), // ind5
	vec3f(0, 1, 1), // ind6
	vec3f(1, 1, 1)  // ind7
];

immutable ushort[3][2][5][4] slopeIndices = [
	[	// ROTATION 0
		[[2, 0, 4], [4, 6, 2]],	// -X
		[[0, 2, 3]],			// -Y
		[[0, 6, 7]],			// +Y
		[[3, 2, 6], [6, 7, 3]],	// +Z
		[[0, 3, 7],	[7, 4, 0]]	// diag
	],
	[	// ROTATION 1
		[[2, 0, 4], [4, 6, 2]],	// -X
		[[1, 0, 2]],			// -Y
		[[4, 6, 5]],			// +Y
		[[0, 1, 5], [5, 4, 0]],	// -Z
		[[1, 2, 6], [6, 5, 1]]	// diag
	],
	[	// ROTATION 2
		[[5, 1, 3], [3, 7, 5]],	// +X
		[[3, 1, 0]],			// -Y
		[[7, 5, 4]],			// +Y
		[[4, 0, 1], [1, 5, 4]],	// -Z
		[[7, 3, 0], [0, 4, 7]]	// diag
	],
	[	// ROTATION 3
		[[1, 3, 7], [7, 5, 1]],	// +X
		[[1, 2, 3]],			// -Y
		[[5, 6, 7]],			// +Y
		[[7, 3, 2], [2, 6, 7]],	// +Z
		[[5, 1, 2], [2, 6, 5]]	// diag
	]
];

immutable vec3f[5][4] slopeNormals = [
	[ // ROTATION 0
		vec3f(-1f, 0f, 0f),
		vec3f(0f, -1f, 0f),
		vec3f(0f, 1f, 0f),
		vec3f(0f, 0f, 1f),
		vec3f(0.5f, 0f, -0.5f)
	],
	[ // ROTATION 1
		vec3f(-1f, 0f, 0f),
		vec3f(0f, -1f, 0f),
		vec3f(0f, 1f, 0f),
		vec3f(0f, 0f, -1f),
		vec3f(0.5f, 0f, 0.5f)
	],
	[ // ROTATION 2
		vec3f(1f, 0f, 0f),
		vec3f(0f, -1f, 0f),
		vec3f(0f, 1f, 0f),
		vec3f(0f, 0f, -1f),
		vec3f(-0.5f, 0f, 0.5f)
	],
	[ // ROTATION 3
		vec3f(1f, 0f, 0f),
		vec3f(0f, -1f, 0f),
		vec3f(0f, 1f, 0f),
		vec3f(0f, 0f, 1f),
		vec3f(-0.5f, 0f, -0.5f)
	]
];

alias SST = SideSolidTable;

final class HorizontalSlope : IBlockVoxelMesh {
	static immutable string technicalStatic = "block_mesh_horizontal_slope";
	mixin(VoxelContentQuick!(technicalStatic, "Horizontal slope", squareOneMod, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	SideSolidTable isSideSolid(Voxel voxel, VoxelSide side) {
		return SST.notSolid;
	}

	void generateMesh(Voxel target, int voxelSkip, ref Voxel[6] neighbours, ref SideSolidTable[6] sidesSolid, vec3i coord, ref vec3f[64] verts, ref vec3f[64] normals, out int vertCount) {
		int v = 0, n = 0;
		
		ubyte rotation = target.meshData & 7;
		
		void addTriag(ushort[3] indices, int dir) {
			foreach(i; 0 .. 3) {
				verts[v++] = cubeVertices[indices[i]] * voxelSkip + coord;
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