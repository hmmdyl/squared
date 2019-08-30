module squareone.voxelcontent.glass.types;

import squareone.voxel;
import squareone.voxelcontent.block.processor;
import squareone.voxelcontent.block.types;
import squareone.util.spec;

import dlib.math.vector;

struct GlassVoxel
{
	Voxel v;
	alias v this;

	this(Voxel v) { this.v = v; }

	@property MeshID trueMesh() const { return v.materialData & meshBits; }
	@property trueMesh(MeshID mid) 
	{
		v.materialData = v.materialData & ~meshBits;
		v.materialData = v.materialData | (mid & meshBits);
	}
}

final class GlassMaterial : IVoxelMaterial
{
	static immutable string technicalStatic = "squareOne:voxel:blockMaterial:glass";
	mixin(VoxelContentQuick!(technicalStatic, "Glass", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }
}

final class GlassMesh : IVoxelMesh
{
	static immutable string technicalStatic = "squareOne:voxel:glassMesh:glass";
	mixin(VoxelContentQuick!(technicalStatic, "Glass", appName, dylanGrahamName));

	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort nid) { id_ = nid; }

	SideSolidTable isSideSolid(Voxel voxel, VoxelSide side) { return SideSolidTable.notSolid; }

	BlockProcessor bp;

	void generateMesh(Voxel target, int voxelSkip, ref Voxel[6] neighbours, ref SideSolidTable[6] sidesSolid, Vector3i coord, ref Vector3f[64] verts, ref Vector3f[64] normals, out int vertCount)
	{
		SideSolidTable[6] correctTable;
		foreach(size_t i, ref SideSolidTable sst; correctTable)
			sst = neighbours[i].mesh == target.mesh ? SideSolidTable.solid : sidesSolid[i];

		MeshID trueMeshID = GlassVoxel(target).trueMesh;
		Voxel blankedTarget = target;
		blankedTarget.materialData = target.materialData & ~0xFFF;
		bp.getMesh(trueMeshID).generateMesh(blankedTarget, voxelSkip, neighbours, correctTable, coord, verts, normals, vertCount);
	}
}

package struct RenderData
{
	uint vertexBO, normalBO, texCoordBO, metaBO;
	float chunkMax, fit10BitScale;
	ushort vertexCount;

	void create()
	{
		import derelict.opengl3.gl3 : glGenBuffers;

		glGenBuffers(1, &vertexBO);
		glGenBuffers(1, &normalBO);
		glGenBuffers(1, &texCoordBO);
		glGenBuffers(1, &metaBO);
	}

	void destroy()
	{
		import derelict.opengl3.gl3 : glDeleteBuffers;

		glDeleteBuffers(1, &vertexBO);
		glDeleteBuffers(1, &normalBO);
		glDeleteBuffers(1, &texCoordBO);
		glDeleteBuffers(1, &metaBO);
	}
}