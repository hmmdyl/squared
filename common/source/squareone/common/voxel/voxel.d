module squareone.common.voxel;

import std.bitmanip;

@safe nothrow @nogc:

struct Voxel 
{
	mixin(bitfields!(
		ushort, "material", 12,
		ushort, "mesh", 12,
		uint, "materialData", 20,
		uint, "meshData", 20));

	this(ushort material, ushort mesh, uint materialData, uint meshData) 
	{
		this.material = material;
		this.mesh = mesh;
		this.materialData = materialData;
		this.meshData = meshData;
	}

	@property Voxel dup() const { return Voxel(this.material, this.mesh, this.materialData, this.meshData); }
}

enum VoxelSide 
{
	nx = 0,
	px = 1,
	ny = 2,
	py = 3,
	nz = 4,
	pz = 5
}