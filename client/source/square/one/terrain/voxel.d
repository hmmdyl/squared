module square.one.terrain.voxel;

struct Voxel {
	ushort material;
	ushort mesh;

	ushort materialData;
	ushort meshData;

	this(ushort material, ushort mesh, ushort materialData, ushort meshData) {
		this.material = material;
		this.mesh = mesh;
		this.materialData = materialData;
		this.meshData = meshData;
	}

	@property Voxel dup() {
		return Voxel(this.material, this.mesh, this.materialData, this.meshData);
	}
}

enum VoxelSide {
	nx = 0,
	px = 1,
	ny = 2,
	py = 3,
	nz = 4,
	pz = 5
}