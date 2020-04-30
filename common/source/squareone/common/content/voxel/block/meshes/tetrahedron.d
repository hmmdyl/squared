module squareone.common.content.voxel.block.meshes.tetrahedron;

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

immutable ushort[3][4][8] tetrahedronIndices = [
	[	// ROTATION 0
		[0, 2, 4], 			// -X
		[1, 2, 0],			// -Y
		[0, 4, 1],			// -Z
		[1, 4, 2]			// diag
	],
	[	// ROTATION 1
		[1, 5, 3],			// +X
		[0, 1, 3],			// -Y
		[1, 0, 5],			// -Z
		[0, 3, 5]			// diag
	],
	[	// ROTATION 2
		[3, 1, 7],			// +X
		[3, 2, 1],			// -Y
		[3, 7, 2],			// +Z
		[2, 7, 1]			// diag
	],
	[	// ROTATION 3
		[2, 6, 0],			// -X
		[2, 0, 3],			// -Y
		[6, 2, 3],			// +Z
		[3, 0, 6],			// diag
	],
	[	// ROTATION 4
		],
	[]
];

immutable Vector3f[4][8] tetrahedronNormals = [
	[	// ROTATION 0
		Vector3f(-1, 0, 0),
		Vector3f(0, -1, 0),
		Vector3f(0, 0, -1),
		Vector3f(0.5f, 0.5f, 0.5f)
	],
	[	// ROTATION 1
		Vector3f(1, 0, 0),
		Vector3f(0, -1, 0),
		Vector3f(0, 0, -1),
		Vector3f(-0.5f, 0.5f, 0.5f)
	],
	[	// ROTATION 2
		Vector3f(1, 0, 0),
		Vector3f(0, -1, 0),
		Vector3f(0, 0, 1),
		Vector3f(-0.5f, 0.5f, -0.5f)
	],
	[
		Vector3f(-1, 0, 0),
		Vector3f(0, -1, 0),
		Vector3f(0, 0, 1),
		Vector3f(0.5f, 0.5f, -0.5f)
	]
	];

alias SST = SideSolidTable;

final class Tetrahedron : IBlockVoxelMesh
{
	static immutable string technicalStatic = "squareOne:voxel:blockMesh:tetrahedron";
	mixin(VoxelContentQuick!(technicalStatic, "Tetrahedron", name, dylanGraham));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	SideSolidTable isSideSolid(Voxel voxel, VoxelSide side) 
	{ 
		ubyte rotation = voxel.meshData & 7;
		final switch(rotation) 
		{
			case 0:
				if(side == VoxelSide.nx) return SST.slope_1_3_2;
				else if(side == VoxelSide.ny) return SST.slope_2_0_1;
				else if(side == VoxelSide.nz) return SST.slope_0_1_3;
				else return SST.notSolid;
			case 1:
				if(side == VoxelSide.px) return SST.slope_0_1_3;
				else if(side == VoxelSide.ny) return SST.slope_0_2_3;
				else if(side == VoxelSide.nz) return SST.slope_1_3_2;
				else return SST.notSolid;
			case 2:
				if(side == VoxelSide.px) return SST.slope_1_3_2;
				else if(side == VoxelSide.ny) return SST.slope_1_3_2;
				else if(side == VoxelSide.pz) return SST.slope_0_1_3;
				else return SST.notSolid;
			case 3:
				if(side == VoxelSide.nx) return SST.slope_0_1_3;
				else if(side == VoxelSide.ny) return SST.slope_0_1_3;
				else if(side == VoxelSide.pz) return SST.slope_1_3_2;
				else return SST.notSolid;
		}
	}

	void finalise(BlockProcessorBase bp) {}

	void generateMesh(Voxel target, int voxelSkip, ref Voxel[6] neighbours, ref SideSolidTable[6] sidesSolid, Vector3i coord, ref Vector3f[64] verts, ref Vector3f[64] normals, out int vertCount) 
	{
		int v, n;
		ubyte rotation = target.meshData & 7;

		void addTriag(ushort[3] indices, int dir) 
		{
			foreach(i; 0 .. 3) 
			{
				verts[v++] = cubeVertices[indices[i]] * voxelSkip + Vector3f(coord);
				normals[n++ ] = tetrahedronNormals[rotation][dir];
			}
		}

		bool allAreSolid = sidesSolid[VoxelSide.nx] == SST.solid && 
			sidesSolid[VoxelSide.px] == SST.solid && 
			sidesSolid[VoxelSide.ny] == SST.solid && 
			sidesSolid[VoxelSide.py] == SST.solid && 
			sidesSolid[VoxelSide.nz] == SST.solid && 
			sidesSolid[VoxelSide.pz] == SST.solid;

		final switch(rotation) 
		{
			case 0:
				if(!(sidesSolid[VoxelSide.nx] == SST.solid || sidesSolid[VoxelSide.nx] == SST.slope_0_1_3))
					addTriag(tetrahedronIndices[0][0], 0);
				//if(!(sidesSolid[VoxelSide.ny] == SST.solid || sidesSolid[VoxelSide.ny] == SST.slope_0_2_3))
				if(!(sidesSolid[VoxelSide.ny] == SST.solid || sidesSolid[VoxelSide.ny] == SST.slope_0_1_3))
					addTriag(tetrahedronIndices[0][1], 1);
				if(!(sidesSolid[VoxelSide.nz] == SST.solid || sidesSolid[VoxelSide.nz] == SST.slope_1_3_2))
					addTriag(tetrahedronIndices[0][2], 2);

				if(!allAreSolid)
					addTriag(tetrahedronIndices[0][3], 3);

				break;
			case 1:
				if(!(sidesSolid[VoxelSide.px] == SST.solid || sidesSolid[VoxelSide.px] == SST.slope_1_3_2)) // issue
					addTriag(tetrahedronIndices[1][0], 0);
				if(!(sidesSolid[VoxelSide.ny] == SST.solid || sidesSolid[VoxelSide.ny] == SST.slope_2_0_1))
					addTriag(tetrahedronIndices[1][1], 1);
				if(!(sidesSolid[VoxelSide.nz] == SST.solid || sidesSolid[VoxelSide.nz] == SST.slope_0_1_3))
					addTriag(tetrahedronIndices[1][2], 2);

				if(!allAreSolid)
					addTriag(tetrahedronIndices[1][3], 3);

				break;
			case 2:
				if(!(sidesSolid[VoxelSide.px] == SST.solid || sidesSolid[VoxelSide.px] == SST.slope_0_1_3))
					addTriag(tetrahedronIndices[2][0], 0);
				if(!(sidesSolid[VoxelSide.ny] == SST.solid || sidesSolid[VoxelSide.ny] == SST.slope_0_2_3))
					addTriag(tetrahedronIndices[2][1], 1);
				if(!(sidesSolid[VoxelSide.pz] == SST.solid || sidesSolid[VoxelSide.pz] == SST.slope_1_3_2))
					addTriag(tetrahedronIndices[2][2], 2);

				if(!allAreSolid)
					addTriag(tetrahedronIndices[2][3], 3);

				break;
			case 3:
				if(!(sidesSolid[VoxelSide.nx] == SST.solid || sidesSolid[VoxelSide.nx] == SST.slope_1_3_2))
					addTriag(tetrahedronIndices[3][0], 0);
				if(!(sidesSolid[VoxelSide.ny] == SST.solid || sidesSolid[VoxelSide.ny] == SST.slope_1_3_2))
					addTriag(tetrahedronIndices[3][1], 1);
				if(!(sidesSolid[VoxelSide.pz] == SST.solid || sidesSolid[VoxelSide.pz] == SST.slope_0_1_3))
					addTriag(tetrahedronIndices[3][2], 2);

				if(!allAreSolid)
					addTriag(tetrahedronIndices[3][3], 3);

				break;
		}

		vertCount = v;
	}
}