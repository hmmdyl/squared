module square.one.voxelcon.block.meshes.slope;

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

immutable ushort[3][2][5][8] slopeIndices = [
	[	// ROTATION 0
		[[0, 2, 6], [6, 4, 0]], // -X
		[[0, 1, 3], [3, 2, 0]], // -Y
		[[0, 4, 1]], 			// -Z
		[[2, 6, 3]],			// +Z
		[[4, 6, 3], [3, 1, 4]]	// diag
		/*[[0, 2, 6], [6, 4, 0]], // -X
	//[[7, 3, 1], [1, 5, 7]], // +X
	[[0, 1, 3], [3, 2, 0]], // -Y
	//[[7, 5, 4], [4, 6, 7]], // +Y
	[[5, 1, 0]], // -Z
	[[2, 3, 7]],  // +Z
	[[5, 0, 2], [2, 7, 5]] // diag*/
	],

	[	// ROTATION 1
		[[1, 3, 5]],			// +X
		[[0, 2, 4]],			// -X
		[[2, 0, 1], [1, 3, 2]],	// -Y
		[[4, 0, 1], [1, 5, 4]], // -Z
		[[5, 3, 2], [2, 4, 5]] // diag
	],

	[	// ROTATION 2
		[[1, 3, 7], [7, 5, 1]],	// +X
		[[0, 2, 3], [3, 1, 0]], // -Y
		[[5, 1, 0]],			// -Z
		[[7, 3, 2]],			// +Z
		[[5, 7, 2], [2, 0, 5]]	// diag
	],

	[	// ROTATION 3
		[[0, 2, 6]],			// -X
		[[1, 3, 7]],			// +X
		[[0, 2, 3], [3, 1, 0]],	// -Y
		[[7, 3, 2], [2, 6, 7]], // -Z
		[[0, 1, 7], [7, 6, 0]]	// diag
	],

	[	// ROTATION 4
		[[0, 4, 6], [6, 2, 0]], // -X
		[[7, 6, 4], [4, 5, 7]], // +Y
		[[5, 4, 0]],			// -Z
		[[7, 2, 6]],			// +Z
		[[5, 0, 2], [2, 7, 5]]	// diag
	],

	[	// ROTATION 5
		[[0, 4, 6]],			// -X
		[[1, 7, 5]],			// +X
		[[4, 5, 7], [7, 6, 4]],	// +Y
		[[0, 1, 5], [5, 4, 0]],	// -Z
		[[1, 0, 6], [6, 7, 1]]	// diag
	],

	[	// ROTATION 6
		[[5, 1, 3], [3, 7, 5]],	// +X
		[[4, 5, 7], [7, 6, 4]], // +Y
		[[4, 1, 5]],			// -Z
		[[3, 6, 7]],			// +Z
		[[6, 3, 1], [1, 4, 6]]	// diag
	],

	[	// ROTATION 7
		[[2, 4, 6]],			// -X
		[[3, 7, 5]],			// +X
		[[4, 5, 7], [7, 6, 4]],	// +Y
		[[7, 3, 2], [2, 6, 7]],	// +Z
		[[4, 2, 3], [3, 5, 4]], // diag
	]
];

immutable vec3f[5][8] cubeNormals = [
	[	// ROTATION 0
		vec3f(-1, 0, 0),		// -X
		vec3f(0, -1, 0),		// -Y
		vec3f(0, 0, -1),		// -Z
		vec3f(0, 0, 1),			// +Z
		vec3f(0.5f, 0.5f, 0f)	// diag
	],

	[	// ROTATION 1
		vec3f(1, 0, 0),			// +X
		vec3f(-1, 0, 0),		// -X
		vec3f(0, -1, 0),		// -Y
		vec3f(0, 0, -1),		// -Z
		vec3f(0, 0.5f, 0.5f)	// diag
	],

	[	// ROTATION 2
		vec3f(1, 0, 0),			// +X
		vec3f(0, -1, 0),		// -Y
		vec3f(0, 0, -1),		// -Z
		vec3f(0, 0, 1),			// +Z
		vec3f(-0.5f, 0.5f, 0)	// diag
	],

	[	// ROTATION 3
		vec3f(-1, 0, 0),		// -X
		vec3f(1, 0, 0),			// +X
		vec3f(0, -1, 0),		// -Y
		vec3f(0, 0, -1),		// -Z
		vec3f(0, 0.5f, -0.5f)	// diag
	],

	[	// ROTATION 4
		vec3f(-1, 0, 0),		// -X
		vec3f(0, 1, 0),			// +Y
		vec3f(0, 0, -1),		// -Z
		vec3f(0, 0, 1),			// +Z
		vec3f(0.5f, -0.5f, 0)	// diag
	],

	[	// ROTATION 5
		vec3f(-1, 0, 0),		// -X
		vec3f(1, 0, 0),			// +X
		vec3f(0, 1, 0),			// +Y
		vec3f(0, 0, -1),		// -Z
		vec3f(0, -0.5f, 0.5f)	// diag
	],

	[	// ROTATION 6
		vec3f(1, 0, 0),			// +X
		vec3f(0, 1, 0),			// +Y
		vec3f(0, 0, -1),		// -Z
		vec3f(0, 0, 1),			// +Z
		vec3f(-0.5f, -0.5f, 0)	// diag
	],

	[	// ROTATION 7
		vec3f(-1, 0, 0),		// -X
		vec3f(1, 0, 0),			// +X
		vec3f(0, 1, 0),			// +Y
		vec3f(0, 0, 1),			// +Z
		vec3f(0, -0.5f, -0.5f)	// diag
	],
];

alias SST = SideSolidTable;

final class Slope : IBlockVoxelMesh {
	static immutable string technicalStatic = "block_mesh_slope";
	mixin(VoxelContentQuick!(technicalStatic, "Slope", squareOneMod, dylanGrahamName));
	
	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }
	
	SideSolidTable isSideSolid(Voxel voxel, VoxelSide side) { 
		ubyte rotation = voxel.meshData & 7;
		final switch(rotation) {
			case 0:
				if(side == VoxelSide.nx || side == VoxelSide.ny) return SST.solid;
				else if(side == VoxelSide.nz) return SST.slope_0_1_3;
				else if(side == VoxelSide.pz) return SST.slope_1_3_2;
				else return SST.notSolid;
			case 1:
				if(side == VoxelSide.nz || side == VoxelSide.ny) return SST.solid;
				else if(side == VoxelSide.nx) return SST.slope_1_3_2;
				else if(side == VoxelSide.px) return SST.slope_0_1_3;
				else return SST.notSolid;
			case 2:
				if(side == VoxelSide.px || side == VoxelSide.ny) return SST.solid;
				else if(side == VoxelSide.nz) return SST.slope_1_3_2;
				else if(side == VoxelSide.pz) return SST.slope_0_1_3;
				else return SST.notSolid;
			case 3:
				if(side == VoxelSide.pz || side == VoxelSide.ny) return SST.solid;
				else if(side == VoxelSide.nx) return SST.slope_0_1_3;
				else if(side == VoxelSide.px) return SST.slope_1_3_2;
				else return SST.notSolid;
			case 4:
				if(side == VoxelSide.nx || side == VoxelSide.py) return SST.solid;
				else if(side == VoxelSide.nz) return SST.slope_2_0_1;
				else if(side == VoxelSide.pz) return SST.slope_0_2_3;
				else return SST.notSolid;
			case 5:
				if(side == VoxelSide.py || side == VoxelSide.nz) return SST.solid;
				else if(side == VoxelSide.nx) return SST.slope_0_2_3;
				else if(side == VoxelSide.px) return SST.slope_2_0_1;
				else return SST.notSolid;
			case 6:
				if(side == VoxelSide.px || side == VoxelSide.py) return SST.solid;
				else if(side == VoxelSide.nz) return SST.slope_0_2_3;
				else if(side == VoxelSide.pz) return SST.slope_2_0_1;
				else return SST.notSolid;
			case 7:
				if(side == VoxelSide.py || side == VoxelSide.pz) return SST.solid;
				else if(side == VoxelSide.nx) return SST.slope_2_0_1;
				else if(side == VoxelSide.px) return SST.slope_0_2_3;
				else return SST.notSolid;
		}
	}
	
	void generateMesh(Voxel target, int voxelSkip, ref Voxel[6] neighbours, ref SideSolidTable[6] sidesSolid, vec3i coord, ref vec3f[64] verts, ref vec3f[64] normals, out int vertCount) {
		int v = 0, n = 0;

		ubyte rotation = target.meshData & 7;

		void addTriag(ushort[3] indices, int dir) {
			foreach(i; 0 .. 3) {
				verts[v++] = cubeVertices[indices[i]] * voxelSkip + coord;
				normals[n++ ] = cubeNormals[rotation][dir];
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
				if(sidesSolid[VoxelSide.nx] != SST.solid) {
					addTriag(slopeIndices[0][0][0], 0);
					addTriag(slopeIndices[0][0][1], 0);
				}
				if(sidesSolid[VoxelSide.ny] != SST.solid) {
					addTriag(slopeIndices[0][1][0], 1);
					addTriag(slopeIndices[0][1][1], 1);
				}
				if(!(sidesSolid[VoxelSide.nz] == SST.solid || sidesSolid[VoxelSide.nz] == SST.slope_1_3_2)) {
					addTriag(slopeIndices[0][2][0], 2);
				}
				if(!(sidesSolid[VoxelSide.pz] == SST.solid || sidesSolid[VoxelSide.pz] == SST.slope_0_1_3)) {
					addTriag(slopeIndices[0][3][0], 3);
				}

				if(!allAreSolid) {
					addTriag(slopeIndices[0][4][0], 4);
					addTriag(slopeIndices[0][4][1], 4);
				}
				break;
			case 1:
				if(!(sidesSolid[VoxelSide.nx] == SST.solid || sidesSolid[VoxelSide.nx] == SST.slope_0_1_3))
					addTriag(slopeIndices[1][1][0], 1);
				if(!(sidesSolid[VoxelSide.px] == SST.solid || sidesSolid[VoxelSide.px] == SST.slope_1_3_2))
					addTriag(slopeIndices[1][0][0], 0);
				if(sidesSolid[VoxelSide.ny] != SST.solid) {
					addTriag(slopeIndices[1][2][0], 2);
					addTriag(slopeIndices[1][2][1], 2);
				}
				if(sidesSolid[VoxelSide.nz] != SST.solid) {
					addTriag(slopeIndices[1][3][0], 3);
					addTriag(slopeIndices[1][3][1], 3);
				}

				if(!allAreSolid) {
					addTriag(slopeIndices[1][4][0], 4);
					addTriag(slopeIndices[1][4][1], 4);
				}
				break;
			case 2:
				if(sidesSolid[VoxelSide.px] != SST.solid) {
					addTriag(slopeIndices[2][0][0], 0);
					addTriag(slopeIndices[2][0][1], 0);
				}
				if(sidesSolid[VoxelSide.ny] != SST.solid) {
					addTriag(slopeIndices[2][1][0], 1);
					addTriag(slopeIndices[2][1][1], 1);
				}
				if(!(sidesSolid[VoxelSide.nz] == SST.solid || sidesSolid[VoxelSide.nz] == SST.slope_0_1_3)) 
					addTriag(slopeIndices[2][2][0], 2);
				if(!(sidesSolid[VoxelSide.pz] == SST.solid || sidesSolid[VoxelSide.pz] == SST.slope_1_3_2))
					addTriag(slopeIndices[2][3][0], 3);

				if(!allAreSolid) {
					addTriag(slopeIndices[2][4][0], 4);
					addTriag(slopeIndices[2][4][1], 4);
				}
				break;
			case 3:
				if(!(sidesSolid[VoxelSide.nx] == SST.solid || sidesSolid[VoxelSide.nx] == SST.slope_1_3_2))
					addTriag(slopeIndices[3][0][0], 0);
				if(!(sidesSolid[VoxelSide.px] == SST.solid || sidesSolid[VoxelSide.px] == SST.slope_0_1_3))
					addTriag(slopeIndices[3][1][0], 1);
				if(sidesSolid[VoxelSide.ny] != SST.solid) {
					addTriag(slopeIndices[3][2][0], 2);
					addTriag(slopeIndices[3][2][1], 2);
				}
				if(sidesSolid[VoxelSide.pz] != SST.solid) {
					addTriag(slopeIndices[3][3][0], 3);
					addTriag(slopeIndices[3][3][1], 3);
				}

				if(!allAreSolid) {
					addTriag(slopeIndices[3][4][0], 4);
					addTriag(slopeIndices[3][4][1], 4);
				}
				break;
			case 4:
				if(!sidesSolid[VoxelSide.nx]) {
					addTriag(slopeIndices[4][0][0], 0);
					addTriag(slopeIndices[4][0][1], 0);
				}
				if(!sidesSolid[VoxelSide.py]) {
					addTriag(slopeIndices[4][1][0], 1);
					addTriag(slopeIndices[4][1][1], 1);
				}
				if(!sidesSolid[VoxelSide.nz])
					addTriag(slopeIndices[4][2][0], 2);
				if(!sidesSolid[VoxelSide.pz])
					addTriag(slopeIndices[4][3][0], 3);

				if(!allAreSolid) {
					addTriag(slopeIndices[4][4][0], 4);
					addTriag(slopeIndices[4][4][1], 4);
				}
				break;
			case 5:
				if(!sidesSolid[VoxelSide.nx]) 
					addTriag(slopeIndices[5][0][0], 0);
				if(!sidesSolid[VoxelSide.px])
					addTriag(slopeIndices[5][1][0], 1);
				if(!sidesSolid[VoxelSide.py]) {
					addTriag(slopeIndices[5][2][0], 2);
					addTriag(slopeIndices[5][2][1], 2);
				}
				if(!sidesSolid[VoxelSide.nz]) {
					addTriag(slopeIndices[5][3][0], 3);
					addTriag(slopeIndices[5][3][1], 3);
				}

				if(!allAreSolid) {
					addTriag(slopeIndices[5][4][0], 4);
					addTriag(slopeIndices[5][4][1], 4);
				}
				break;
			case 6:
				if(!sidesSolid[VoxelSide.px]) {
					addTriag(slopeIndices[6][0][0], 0);
					addTriag(slopeIndices[6][0][1], 0);
				}
				if(!sidesSolid[VoxelSide.py]) {
					addTriag(slopeIndices[6][1][0], 1);
					addTriag(slopeIndices[6][1][1], 1);
				}
				if(!sidesSolid[VoxelSide.nz])
					addTriag(slopeIndices[6][2][0], 2);
				if(!sidesSolid[VoxelSide.pz])
					addTriag(slopeIndices[6][3][0], 3);

				if(!allAreSolid) {
					addTriag(slopeIndices[6][4][0], 4);
					addTriag(slopeIndices[6][4][1], 4);
				}
				break;
			case 7:
				if(!sidesSolid[VoxelSide.nx]) 
					addTriag(slopeIndices[7][0][0], 0);
				if(!sidesSolid[VoxelSide.px])
					addTriag(slopeIndices[7][1][0], 1);
				if(!sidesSolid[VoxelSide.py]) {
					addTriag(slopeIndices[7][2][0], 2);
					addTriag(slopeIndices[7][2][1], 2);
				}
				if(!sidesSolid[VoxelSide.pz]) {
					addTriag(slopeIndices[7][3][0], 3);
					addTriag(slopeIndices[7][3][1], 3);
				}

				if(!allAreSolid) {
					addTriag(slopeIndices[7][4][0], 4);
					addTriag(slopeIndices[7][4][1], 1);
				}
				break;
		}

		vertCount = v;
	}
}