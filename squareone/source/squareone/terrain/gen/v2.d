module squareone.terrain.gen.v2;

import squareone.terrain.gen.noisegen;
import squareone.voxel;
import squareone.util.procgen;
import squareone.voxelutils.smoother;

import moxane.core;
import moxane.utils.maybe;

import dlib.math;

import std.concurrency;
import core.atomic;

class GenV2 : NoiseGenerator2
{
	private IChannel!NoiseGeneratorOrder source_;
	@property IChannel!NoiseGeneratorOrder source() { return source_; }

	private shared float averageMeshTime_ = 0f;
	@property float averageMeshTime() { return atomicLoad(averageMeshTime_); }

	private shared bool parked_ = true, terminated_ = false;
	@property bool parked() const { return atomicLoad(parked_); }
	private @property void parked(bool n) { return atomicStore(parked_, n); }
	@property bool terminated() const { return atomicLoad(terminated_); }
	private @property void terminated(bool n) { atomicStore(terminated_, n); }

	private Tid thread;

	this(NoiseGeneratorManager2 manager, Resources resources, IChannel!NoiseGeneratorOrder source)
	in(manager !is null) in(resources !is null) in(source !is null)
	{
		super(manager, resources);
		this.source_ = source;

		thread = spawn(&worker, cast(shared)this);
	}

	void kick() { send(thread, true); }
	void terminate() { send(thread, false); }
}

private enum int overrun = ChunkData.voxelOffset + 1;
private enum int overrunDimensions = ChunkData.chunkDimensions + overrun * 2;
private enum int overrunDimensions3 = overrunDimensions ^^ 3;

private void worker(shared GenV2 ngs)
{
	GenV2 ng = cast(GenV2)ngs;
	
	Meshes meshes = Meshes.get(ng.resources);
	Materials materials = Materials.get(ng.resources);
	SmootherConfig smootherCfg = 
	{
		root : meshes.cube,
		inv : meshes.invisible,
		cube : meshes.cube,
		slope : meshes.slope,
		tetrahedron : meshes.tetrahedron,
		antiTetrahedron : meshes.antiTetrahedron,
		horizontalSlope : meshes.horizontalSlope
	};

	VoxelBuffer raw = VoxelBuffer(overrunDimensions, overrun), 
		smootherOutput = VoxelBuffer(overrunDimensions, overrun);

	while(!ng.terminated)
	{
		receive(
				(bool status)
				{
					if(status == false)
					{
						ng.terminated = true;
						return;
					}

					ng.parked = false;
					scope(exit) ng.parked = true;

					bool consuming = true;
					while(consuming)
					{
						Maybe!NoiseGeneratorOrder order = ng.source.tryGet;
						if(order.isNull)
							consuming = false;
						else
						{}//operate(*order.unwrap, ng, simplex, meshes, materials, smootherCfg, raw, smootherOutput);
					}
				}
			);
	}
}

private struct Meshes
{
	ushort invisible,
		cube,
		slope,
		tetrahedron,
		antiTetrahedron,
		horizontalSlope,
		fluid,
		grassBlades,
		leaf,
		glass;

	static Meshes get(Resources resources)
	{
		import squareone.voxelcontent.block.meshes;
		import squareone.voxelcontent.fluid.processor;
		import squareone.voxelcontent.vegetation;
		import squareone.voxelcontent.glass;

		Meshes meshes;
		meshes.invisible = resources.getMesh(Invisible.technicalStatic).id;
		meshes.cube = resources.getMesh(Cube.technicalStatic).id;
		meshes.slope = resources.getMesh(Slope.technicalStatic).id;
		meshes.tetrahedron = resources.getMesh(Tetrahedron.technicalStatic).id;
		meshes.antiTetrahedron = resources.getMesh(AntiTetrahedron.technicalStatic).id;
		meshes.horizontalSlope = resources.getMesh(HorizontalSlope.technicalStatic).id;
		meshes.fluid = resources.getMesh(FluidMesh.technicalStatic).id;
		meshes.grassBlades = resources.getMesh(GrassMesh.technicalStatic).id;
		meshes.leaf = resources.getMesh(LeafMesh.technicalStatic).id;
		meshes.glass = resources.getMesh(GlassMesh.technicalStatic).id;
		return meshes;
	}
}

private struct Materials
{
	ushort air,
		dirt,
		grass,
		sand,
		water,
		grassBlade,
		stone,
		glass;

	static Materials get(Resources resources)
	{
		import squareone.voxelcontent.block.materials;
		import squareone.voxelcontent.fluid.processor;
		import squareone.voxelcontent.vegetation.materials;
		import squareone.voxelcontent.glass;

		Materials m;
		m.air =			resources.getMaterial(Air.technicalStatic).id;
		m.dirt =		resources.getMaterial(Dirt.technicalStatic).id;
		m.grass =		resources.getMaterial(Grass.technicalStatic).id;
		m.sand =		resources.getMaterial(Sand.technicalStatic).id;
		m.water =		0;
		m.grassBlade =	resources.getMaterial(GrassBlade.technicalStatic).id;
		m.stone	=		resources.getMaterial(Stone.technicalStatic).id;
		m.glass =		resources.getMaterial(GlassMaterial.technicalStatic).id;

		return m;
	}
}

private struct VoxelBuffer
{
	Voxel[] voxels;
	const int dimensions, offset;

	this(const int dimensions, const int offset)
	{
		this.dimensions = dimensions;
		this.offset = offset;
		this.voxels = new Voxel[]((dimensions + offset * 2) ^^ 3);
	}

	void dupFrom(const ref VoxelBuffer other)
	in {
		assert(other.dimensions == dimensions);
		assert(other.offset == offset);
		assert(other.voxels.length == voxels.length);
	}
	do { foreach(size_t i, Voxel voxel; other.voxels) voxels[i] = voxel; }

	private size_t fltIdx(int x, int y, int z) const
	{ return x + dimensions * (y + dimensions * z); }

	Voxel get(int x, int y, int z) const 
		in {
			assert(x >= -offset && x < dimensions + offset);
			assert(y >= -offset && y < dimensions + offset);
			assert(z >= -offset && z < dimensions + offset);
		}
	do { return voxels[fltIdx(x + offset, y + offset, z + offset)]; }

	void set(int x, int y, int z, Voxel voxel)
	in {
		assert(x >= -offset && x < dimensions + offset);
		assert(y >= -offset && y < dimensions + offset);
		assert(z >= -offset && z < dimensions + offset);
	}
	do { voxels[fltIdx(x + offset, y + offset, z + offset)] = voxel; }
}