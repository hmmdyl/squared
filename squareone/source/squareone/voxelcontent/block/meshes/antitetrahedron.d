module squareone.voxelcontent.block.meshes.antitetrahedron;

import squareone.voxelcontent.block.processor;
import squareone.voxelcontent.block.types;
import squareone.voxel;
import squareone.util.spec;

import dlib.math;

private immutable Vector3f[8] cubeVertices = [
	Vector3f(0, 0, 0), // ind0
	Vector3f(1, 0, 0), // ind1
	Vector3f(0, 0, 1), // ind2
	Vector3f(1, 0, 1), // ind3
	Vector3f(0, 1, 0), // ind4
	Vector3f(1, 1, 0), // ind5
	Vector3f(0, 1, 1), // ind6
	Vector3f(1, 1, 1)  // ind7
];

private immutable ushort[3][2][7][8] antitetrahedronIndices = [
	[	// ROTATION 0
		[[4, 6, 2], [2, 0, 4]],	// -X
		[[5, 1, 3]],			// +X
		[[2, 3, 1], [1, 0, 2]],	// -Y
		[[6, 4, 5]],			// +Y
		[[4, 0, 1],	[1, 5, 4]],	// -Z
		[[6, 3, 2]],			// +Z
		[[5, 3, 6]]				// diag
	],
	[	// ROTATION 1
		[[2, 0, 4]],			// -X
		[[5, 1, 3], [3, 7, 5]],	// +X
		[[0, 2, 3], [3, 1, 0]],	// -Y
		[[4, 5, 7]],			// +Y
		[[4, 0, 1], [1, 5, 4]],	// -Z
		[[7, 3, 2]],			// +Z
		[[7, 2, 4]],			// diag
	],
	[	// ROTATION 2
		[[6, 2, 0]],			// -X
		[[5, 1, 3], [3, 7, 5]],	// +X
		[[0, 2, 3], [3, 1, 0]],	// -Y
		[[6, 5, 7]],			// +Y
		[[0, 1, 5]],			// -Z
		[[7, 3, 2], [2, 6, 7]],	// +Z
		[[0, 5, 6]]				// diag
	],
	[	// ROTATION 3
		[[2, 0, 4], [4, 6, 2]],	// -X
		[[1, 3, 7]],			// +X
		[[0, 2, 3], [3, 1, 0]],	// -Y
		[[4, 7, 6]],			// +Y
		[[4, 0, 1]],			// -Z
		[[7, 3, 2], [2, 6, 7]],	// +Z
		[[4, 1, 7]]				// diag
	],
	];

template CardinalAxisNormals(string diag) {
	const char[] CardinalAxisNormals = "
	[
		Vector3f(-1, 0, 0),
		Vector3f(1, 0, 0),
		Vector3f(0, -1, 0),
		Vector3f(0, 1, 0),
		Vector3f(0, 0, -1),
		Vector3f(0, 0, 1)," 
		~ diag ~ ",
		]";
}

private immutable Vector3f[7][8] antitetrahedronNormals = [
	mixin(CardinalAxisNormals!("Vector3f(0.5f, 0.5f, 0.5f)")),		// ROTATION 0
	mixin(CardinalAxisNormals!("Vector3f(-0.5f, 0.5f, 0.5f)")),	// ROTATION 1
	mixin(CardinalAxisNormals!("Vector3f(-0.5f, 0.5f, -0.5f)")),	// ROTATION 2
	mixin(CardinalAxisNormals!("Vector3f(0.5f, 0.5f, -0.5f)")),	// ROTATION 3
];

alias SST = SideSolidTable;

final class AntiTetrahedron : IBlockVoxelMesh {
	static immutable string technicalStatic = "squareOne:voxel:blockMesh:antitetrahedron";
	mixin(VoxelContentQuick!(technicalStatic, "Anti-Tetrahedron", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	SideSolidTable isSideSolid(Voxel voxel, VoxelSide side) { 
		ubyte rotation = voxel.meshData & 7;
		final switch(rotation) {
			case 0:
				if(side == VoxelSide.nx) return SST.solid;
				else if(side == VoxelSide.px) return SST.slope_0_1_3;
				else if(side == VoxelSide.ny) return SST.solid;
				else if(side == VoxelSide.py) return SST.slope_0_1_3;
				else if(side == VoxelSide.nz) return SST.solid;
				else /*if(side == VoxelSide.pz)*/ return SST.slope_1_3_2;
			case 1:
				if(side == VoxelSide.nx) return SST.slope_1_3_2;
				else if(side == VoxelSide.px) return SST.solid;
				else if(side == VoxelSide.ny) return SST.solid;
				else if(side == VoxelSide.py) return SST.slope_1_3_2;
				else if(side == VoxelSide.nz) return SST.solid;
				else /*if(side == VoxelSide.pz)*/ return SST.slope_0_1_3;
			case 2:
				if(side == VoxelSide.nx) return SST.slope_0_1_3;
				else if(side == VoxelSide.px) return SST.solid;
				else if(side == VoxelSide.ny) return SST.solid;
				else if(side == VoxelSide.py) return SST.slope_0_2_3;
				else if(side == VoxelSide.nz) return SST.slope_1_3_2;
				else return SST.solid;
			case 3:
				if(side == VoxelSide.nx) return SST.solid;
				else if(side == VoxelSide.px) return SST.slope_1_3_2;
				else if(side == VoxelSide.ny) return SST.solid;
				else if(side == VoxelSide.py) return SST.slope_2_0_1;
				else if(side == VoxelSide.nz) return SST.slope_0_1_3;
				else return SST.solid;
		}
	}

	void finalise(BlockProcessor bp) {}

	void generateMesh(Voxel target, int voxelSkip, ref Voxel[6] neighbours, ref SideSolidTable[6] sidesSolid, Vector3i coord, ref Vector3f[64] verts, ref Vector3f[64] normals, out int vertCount) {
		int v = 0, n = 0;
		scope(exit) vertCount = v;

		ubyte rotation = target.meshData & 7;

		void addTriag(ushort[3] indices, int dir) {
			foreach(i; 0 .. 3) {
				verts[v++] = cubeVertices[indices[i]] * voxelSkip + Vector3f(coord);
				normals[n++ ] = antitetrahedronNormals[rotation][dir];
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
					addTriag(antitetrahedronIndices[0][0][0], 0);
					addTriag(antitetrahedronIndices[0][0][1], 0);
				}
				if(!(sidesSolid[VoxelSide.px] == SST.solid || sidesSolid[VoxelSide.px] == SST.slope_1_3_2)) 
					addTriag(antitetrahedronIndices[0][1][0], 1);
				if(sidesSolid[VoxelSide.ny] != SST.solid) {
					addTriag(antitetrahedronIndices[0][2][0], 2);
					addTriag(antitetrahedronIndices[0][2][1], 2);
				}
				if(!(sidesSolid[VoxelSide.py] == SST.solid || sidesSolid[VoxelSide.py] == SST.slope_2_0_1)) 
					addTriag(antitetrahedronIndices[0][3][0], 3);
				if(sidesSolid[VoxelSide.nz] != SST.solid) {
					addTriag(antitetrahedronIndices[0][4][0], 4);
					addTriag(antitetrahedronIndices[0][4][1], 4);
				}
				if(!(sidesSolid[VoxelSide.pz] == SST.solid || sidesSolid[VoxelSide.pz] == SST.slope_0_1_3)) 
					addTriag(antitetrahedronIndices[0][5][0], 5);

				if(!allAreSolid) 
					addTriag(antitetrahedronIndices[0][6][0], 6);

				break;
			case 1:
				if(!(sidesSolid[VoxelSide.nx] == SST.solid || sidesSolid[VoxelSide.nx] == SST.slope_0_1_3))
					addTriag(antitetrahedronIndices[1][0][0], 0);
				if(sidesSolid[VoxelSide.px] != SST.solid) {
					addTriag(antitetrahedronIndices[1][1][0], 1);
					addTriag(antitetrahedronIndices[1][1][1], 1);
				}
				if(sidesSolid[VoxelSide.ny] != SST.solid) {
					addTriag(antitetrahedronIndices[1][2][0], 2);
					addTriag(antitetrahedronIndices[1][2][1], 2);
				}
				if(!(sidesSolid[VoxelSide.py] == SST.solid || sidesSolid[VoxelSide.py] == SST.slope_0_1_3))
					addTriag(antitetrahedronIndices[1][3][0], 3);
				if(sidesSolid[VoxelSide.nz] != SST.solid) {
					addTriag(antitetrahedronIndices[1][4][0], 4);
					addTriag(antitetrahedronIndices[1][4][1], 4);
				}
				if(!(sidesSolid[VoxelSide.pz] == SST.solid || sidesSolid[VoxelSide.pz] == SST.slope_1_3_2))
					addTriag(antitetrahedronIndices[1][5][0], 5);

				if(!allAreSolid)
					addTriag(antitetrahedronIndices[1][6][0], 6);

				break;
			case 2:
				if(!(sidesSolid[VoxelSide.nx] == SST.solid || sidesSolid[VoxelSide.nx] ==  SST.slope_1_3_2))
					addTriag(antitetrahedronIndices[2][0][0], 0);
				if(sidesSolid[VoxelSide.px] != SST.solid) {
					addTriag(antitetrahedronIndices[2][1][0], 1);
					addTriag(antitetrahedronIndices[2][1][1], 1);
				}
				if(sidesSolid[VoxelSide.ny] != SST.solid) {
					addTriag(antitetrahedronIndices[2][2][0], 2);
					addTriag(antitetrahedronIndices[2][2][1], 2);
				}
				if(!(sidesSolid[VoxelSide.py] == SST.solid || sidesSolid[VoxelSide.py] == SST.slope_2_0_1))
					addTriag(antitetrahedronIndices[2][3][0], 3);
				if(!(sidesSolid[VoxelSide.nz] == SST.solid || sidesSolid[VoxelSide.nz] == SST.slope_0_1_3))
					addTriag(antitetrahedronIndices[2][4][0], 4);
				if(sidesSolid[VoxelSide.pz] != SST.solid) {
					addTriag(antitetrahedronIndices[2][5][0], 5);
					addTriag(antitetrahedronIndices[2][5][1], 5);
				}

				if(!allAreSolid)
					addTriag(antitetrahedronIndices[2][6][0], 6);

				break;
			case 3:
				if(sidesSolid[VoxelSide.nx] != SST.solid) {
					addTriag(antitetrahedronIndices[3][0][0], 0);
					addTriag(antitetrahedronIndices[3][0][1], 0);
				}
				if(!(sidesSolid[VoxelSide.px] == SST.solid || sidesSolid[VoxelSide.px] == SST.slope_0_1_3))
					addTriag(antitetrahedronIndices[3][1][0], 1);
				if(sidesSolid[VoxelSide.ny] != SST.solid) {
					addTriag(antitetrahedronIndices[3][2][0], 2);
					addTriag(antitetrahedronIndices[3][2][1], 2);
				}
				if(!(sidesSolid[VoxelSide.py] == SST.solid || sidesSolid[VoxelSide.py] == SST.slope_0_2_3))
					addTriag(antitetrahedronIndices[3][3][0], 3);
				if(!(sidesSolid[VoxelSide.nz] == SST.solid || sidesSolid[VoxelSide.nz] == SST.slope_1_3_2))
					addTriag(antitetrahedronIndices[3][4][0], 4);
				if(sidesSolid[VoxelSide.pz] != SST.solid) {
					addTriag(antitetrahedronIndices[3][5][0], 5);
					addTriag(antitetrahedronIndices[3][5][1], 5);
				}

				if(!allAreSolid)
					addTriag(antitetrahedronIndices[3][6][0], 6);

				break;
		}
	}
}