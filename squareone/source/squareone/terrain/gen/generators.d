module squareone.terrain.gen.generators;

import squareone.terrain.gen.noisegen;
import squareone.voxel;
import squareone.util.procgen;
import squareone.util.voxel.smoother;

import moxane.core;
import moxane.utils.maybe;

import dlib.math.vector;
import dlib.math.utils;

import std.concurrency;
import core.atomic;
import std.math;

class DefaultNoiseGeneratorV1 : NoiseGenerator2
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

private void worker(shared DefaultNoiseGeneratorV1 ngs)
{
	DefaultNoiseGeneratorV1 ng = cast(DefaultNoiseGeneratorV1)ngs;

	OpenSimplexNoise!float simplex = new OpenSimplexNoise!float;
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
						import std.stdio;
						writeln("terminating");
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
						{
							operate(*order.unwrap, ng, simplex, meshes, materials, smootherCfg, raw, smootherOutput);
						}
					}
				}
		);
	}

	import std.stdio;
	writeln("end", ng.terminated);
}

private void operate(NoiseGeneratorOrder order, DefaultNoiseGeneratorV1 ng, OpenSimplexNoise!float simplex, ref Meshes meshes, ref Materials materials, ref SmootherConfig smootherCfg, ref VoxelBuffer raw, ref VoxelBuffer smootherOutput)
{
	scope(success)
	{
		order.chunk.dataLoadCompleted = true;
		order.chunk.dataLoadBlocking = false;
	}

	if(!order.loadChunk && !order.loadRing) { return; }

	const int s = (order.loadRing ? -overrun : 0) * order.chunk.blockskip;
	const int e = (order.loadRing ? order.chunk.dimensionsProper + overrun : order.chunk.dimensionsProper) * order.chunk.blockskip;

	int premC = generateNoise(order, simplex, s, e, materials, meshes, raw);
	runSmoother(order, raw, smootherOutput, smootherCfg);
	addGrassBlades(order, s, e, premC, meshes, materials, smootherOutput, simplex);
	postProcess(order, premC, smootherOutput);
	countAir(order, meshes);
}

private int generateNoiseBiome(NoiseGeneratorOrder order, OpenSimplexNoise!float, int s, int e, const ref Materials materials, const ref Meshes meshes, ref VoxelBuffer voxels)
{
	int preliminaryCount = 0;

	for(int box = s; box < e; box += order.chunk.blockskip)
	{
		//for()
		//for()
	}

	return preliminaryCount;
}

private int generateNoise(NoiseGeneratorOrder order, OpenSimplexNoise!float simplex, int s, int e, const ref Materials materials, const ref Meshes meshes, ref VoxelBuffer raw)
{
	int premC = 0;

	for(int box = s; box < e; box += order.chunk.blockskip)
	for(int boz = s; boz < e; boz += order.chunk.blockskip)
	{
		if(!order.loadChunk)
			if(box >= 1 && boz >= 1 && box < order.chunk.dimensionsProper - 1 && boz < order.chunk.dimensionsProper - 1)
				continue;

		Vector3d realPos = order.chunkPosition.toVec3dOffset(BlockOffset(box, 0, boz));

		//float height = voronoi(Vector2f(realPos.xz) / 16f, simplex).x * 8f;
		//height = height > 0f ? height : 0f;
		//float height = voronoi2D(Vector2f(realPos.xz) / 8f) * 8f;

		// nice terrain
		//float height = multiNoise(simplex, realPos.x, realPos.z, 64f, 16) * 8f;

		//float height = (redistributeNoise(multiNoise(simplex, realPos.x, realPos.z, 16f, 16) - 0.5f, 4f) - 0.5f) * 8f;

		// icicyles
		//float height = redistributeNoise(multiNoise(simplex, realPos.x, realPos.z, 16f, 16), 8f) * 8f;

		// SWAMP
		//float height = multiNoise(simplex, realPos.x, realPos.z, 16f, 16);


		auto simplexSrc = (float x, float y) => simplex.eval(x, y);
		auto simplexSrc3D = (float x, float y, float z) => simplex.eval(x, y, z);
		auto voronoiSrc = (float x, float y) => voronoi(Vector2f(x, y), simplexSrc).x;

		float flat() { return 0f; }

		float ridgenoise(float n) {
			return 2 * (0.5f - abs(0.5f - n));
		}

		float icicycle()
		{
			float i = redistributeNoise(multiNoise(simplexSrc, realPos.x, realPos.z, 16f, 16), 8f) * 8f;
			float b = multiNoise(simplexSrc, realPos.x, realPos.z, 64, 8) * 3;

			if(i > 0.5)
				return i + b;
			return b;
		}

		float archipelago()
		{
			float h = multiNoise(simplexSrc, realPos.x, realPos.z, 90f, 8) * 4f;
			return h;
		}

		float mountains()
		{
			float h = multiNoise(simplexSrc, realPos.x, realPos.z, 1024f, 16) * 128f;
			return h;
		}

		float swamp()
		{
			float h = multiNoise(simplexSrc, realPos.x, realPos.z, 6f, 4);
			return h;
		}

		float canyon()
		{
			enum voronoiScale = 128;
			enum voronoiPower = 2;
			enum voronoiOffsetPosScale = 32f;
			enum voronoiOffsetScale = 0.1f;
			enum cutoffBase = 0.2f, cutoffUpper = cutoffBase * 1.5f;
			enum canyonBottomHeight = 0;
			enum canyonPlateauHeight = 4;

			import std.math;
			//float factor = redistributeNoise(voronoi(Vector2f(realPos.xz) / voronoiScale, simplexSrc).x, voronoiPower);
			//float factor = voronoi(Vector2f(realPos.xz) / voronoiScale, simplexSrc).x;
			float factor = multiNoise(simplexSrc, realPos.x, realPos.z, voronoiOffsetPosScale, 8);
			factor = ridgenoise(factor);

			//float h = (factor) * 1;// > 0.4f ? 0f : 5f;

			float h;
			if(factor > 0.7f)
				h = canyonBottomHeight + multiNoise(simplexSrc, realPos.x, realPos.z, 8f, 1) * 0.5f;
			else h = canyonPlateauHeight + multiNoise(simplexSrc, realPos.x, realPos.z, 8f, 4) * 2;
			return h;
		}

		float height = mountains;//ridgenoise(multiNoise(simplexSrc, realPos.x, realPos.z, 32, 8) * 8);

		MaterialID upperMat = materials.grass;
		/+float mdet = voronoi(Vector2f(realPos.xz) / 8f, simplexSrc).x;
		if(mdet < 0.333f) upperMat = materials.dirt;
		else if(mdet >= 0.333f && mdet < 0.666f) upperMat = materials.grass;
		else if(mdet > 0.666f) upperMat = materials.stone;+/

		for(int boy = s; boy < e; boy += order.chunk.blockskip)
		{
			if(!order.loadChunk)
				if(box >= 1 && boz >= 1 && boy >= 1 && box < order.chunk.dimensionsProper - 1 && boz < order.chunk.dimensionsProper - 1 && boy < order.chunk.dimensionsProper - 1)
					continue;
			Vector3d realPos1 = order.chunkPosition.toVec3dOffset(BlockOffset(box, boy, boz));
			float cave = 0f;//multiNoise(simplexSrc3D, realPos1.x, realPos1.y, realPos1.z, 32f, 8);

			if(realPos1.y <= height && cave < 0.7f)
				raw.set(box / order.chunk.blockskip, boy / order.chunk.blockskip, boz / order.chunk.blockskip, Voxel(realPos1.y < 0.5 ? materials.sand : upperMat, meshes.cube, 0, 0));
			else
			{
				if(realPos1.y <= 0)
				{
					raw.set(box / order.chunk.blockskip, boy / order.chunk.blockskip, boz / order.chunk.blockskip, Voxel(materials.water, meshes.fluid, 0, 0));
					//premC--;
				}
				else
				{
					raw.set(box / order.chunk.blockskip, boy / order.chunk.blockskip, boz / order.chunk.blockskip, Voxel(0, meshes.invisible, 0, 0));
					premC++;
				}
			}
		}
	}

	return premC;
}

private template loadChunkSkip(string x = "x", string y = "y", string z = "z")
{
	const char[] loadChunkSkip = "
		if(!order.loadChunk)
		if("~x~">= 1 && "~y~">= 1 && "~z~" >= 1 && 
		"~x~" < order.chunk.dimensionsProper - 1 && 
		"~y~" < order.chunk.dimensionsProper - 1 && 
		"~z~" < order.chunk.dimensionsProper - 1)

		continue;";
}

private void addGrassBlades(NoiseGeneratorOrder order, const int s, const int e, ref int premC, const ref Meshes meshes, const ref Materials materials, ref VoxelBuffer smootherOutput, OpenSimplexNoise!float simplex)
{
	import squareone.content.voxel.vegetation;
	import std.math : floor;

	foreach(x; s..e)
	foreach_reverse(y; s+1..e)
	foreach(z; s..e)
	{
		mixin(loadChunkSkip!());

		Voxel ny = smootherOutput.get(x, y - 1, z);
		Voxel v = smootherOutput.get(x, y, z);

		if(v.mesh == meshes.invisible && ny.mesh != meshes.invisible && ny.mesh != meshes.fluid && ny.material == materials.grass)
		{
			Vector3d realPos = order.chunkPosition.toVec3dOffset(BlockOffset(x, y, z));
			ubyte offset = cast(ubyte)(simplex.eval(realPos.x * 2, realPos.z * 2) * 8f);

			GrassVoxel gv = GrassVoxel(Voxel(materials.grassBlade, meshes.grassBlades, 0, 0));
			gv.offset = offset;
			gv.blockHeightCode = 3;
			Vector3f colour;
			colour.x = 27 / 255f;
			colour.y = 191 / 255f;
			colour.z = 46 / 255f;
			gv.colour = colour;

			smootherOutput.set(x, y, z, gv.v);

			premC--;
		}
	}
}

private void runSmoother(NoiseGeneratorOrder o, ref VoxelBuffer raw, ref VoxelBuffer smootherOutput, SmootherConfig smootherCfg)
{
	if(true)
		smoother(raw.voxels, smootherOutput.voxels, o.chunk.overrun, o.chunk.dimensionsProper + o.chunk.overrun, overrunDimensions, smootherCfg);
	else
		smootherOutput.dupFrom(raw);
}

private void postProcess(NoiseGeneratorOrder order, int premC, ref VoxelBuffer smootherOutput)
{
	const int s = -order.chunk.overrun;
	const int e = order.chunk.dimensionsProper + order.chunk.overrun;
	if(premC < overrunDimensions3)
	{
		foreach(x; s..e)
		foreach(y; s..e)
		foreach(z; s..e)
		{
			if(!order.loadChunk)
				if(x >= 0 && y >= 0 && z >= 0 && x < order.chunk.dimensionsProper && z < order.chunk.dimensionsProper && y < order.chunk.dimensionsProper)
					continue;
			order.chunk.set(x * order.chunk.blockskip, y * order.chunk.blockskip, z * order.chunk.blockskip, smootherOutput.get(x, y, z));
		}
	}
	else
	{
		foreach(x; s..e)
		foreach(y; s..e)
		foreach(z; s..e)
		{
			if(!order.loadChunk)
				if(x >= 0 && y >= 0 && z >= 0 && x < order.chunk.dimensionsProper && z < order.chunk.dimensionsProper && y < order.chunk.dimensionsProper)
					continue;

			order.chunk.set(x * order.chunk.blockskip, y * order.chunk.blockskip, z * order.chunk.blockskip, smootherOutput.get(x, y, z));
		}
	}
}

private void countAir(NoiseGeneratorOrder order, const ref Meshes meshes)
{
	const int s = -order.chunk.overrun;
	const int e = order.chunk.dimensionsProper + order.chunk.overrun;
	int airCount, solidCount, fluidCount;

	foreach(x; s..e)
	foreach(y; s..e)
	foreach(z; s..e)
	{
		if(!order.loadChunk)
			if(x >= 0 && y >= 0 && z >= 0 && x < order.chunk.dimensionsProper && z < order.chunk.dimensionsProper && y < order.chunk.dimensionsProper)
				continue;

		Voxel voxel = order.chunk.get(x * order.chunk.blockskip, y * order.chunk.blockskip, z * order.chunk.blockskip);
		if(voxel.mesh == meshes.invisible)
			airCount++;
		else if(voxel.mesh == meshes.fluid)
			fluidCount++;
		else 
			solidCount++;
	}
	order.chunk.airCount = airCount;
	order.chunk.solidCount = solidCount;
	order.chunk.fluidCount = fluidCount;
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
		import squareone.content.voxel.block.meshes;
		import squareone.content.voxel.fluid.processor;
		import squareone.content.voxel.vegetation;
		import squareone.content.voxel.glass;

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
		import squareone.content.voxel.block.materials;
		import squareone.content.voxel.fluid.processor;
		import squareone.content.voxel.vegetation.materials;
		import squareone.content.voxel.glass;

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