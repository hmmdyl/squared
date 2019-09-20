module squareone.terrain.gen.noisegen;

import moxane.core : Moxane, Log, Channel;
import moxane.utils.maybe;
import squareone.voxel;
import squareone.util.procgen.simplex;
import squareone.voxelutils.smoother;
import squareone.util.procgen.voronoi;
import squareone.util.procgen.compose;

import containers.cyclicbuffer;
import dlib.math.vector;
import std.math;
import core.thread;
import core.sync.condition;
import core.atomic;

struct NoiseGeneratorOrder
{
	ILoadableVoxelBuffer chunk;
	ChunkPosition chunkPosition;
	Fiber fiber;

	bool loadRing, loadChunk;

	this(ILoadableVoxelBuffer chunk, ChunkPosition position, Fiber fiber, bool loadChunk, bool loadRing)
	{
		this.chunk = chunk;
		this.chunkPosition = position;
		this.fiber = fiber;
		this.loadChunk = loadChunk;
		this.loadRing = loadRing;
	}
}

class NoiseGeneratorManager 
{
	protected CyclicBuffer!(NoiseGenerator) generators;

	Resources resources;

	public alias createNGDel = NoiseGenerator delegate();
	private createNGDel createNG;

	const long seed;

	private CyclicBuffer!NoiseGeneratorOrder completed;
	private Object completedLock;

	this(Resources resources, int threadNum, createNGDel createNG, long seed) 
	{
		this.resources = resources;
		this.createNG = createNG;
		this.seed = seed;

		threadCount = threadNum;
		completedLock = new Object;
	}

	~this()
	{
		while(!generators.empty)
		{
			NoiseGenerator generator = generators.front;
			generators.removeFront;
			generator.terminate = true;
			destroy(generator);
			//delete generator;
		}
	}

	void pumpCompletedQueue()
	{
		size_t l;
		synchronized(completedLock) l = completed.length;

		foreach(i; 0 .. l)
		{
			NoiseGeneratorOrder order;
			synchronized(completedLock)
			{
				order = completed.front;
				completed.removeFront;
			}
			if(order.fiber !is null)
				order.fiber.call;
		}
	}

	double averageTime = 0, lowestTime = 0, highestTime = 0;

	private __gshared uint threadCount_ = 0;
	@property uint threadCount() { return threadCount_; }
	@property void threadCount(uint tc) {
		setNumTreads(tc);
		threadCount_ = tc;
	}

	@property uint numBusy() {
		uint n = 0;
		foreach(NoiseGenerator ng; generators) 
			if(ng.busy)
				n++;
		return n;
	}

	private void setNumTreads(uint tc) 
	{
		if(tc < threadCount_) 
		{
			int diff = threadCount_ - tc;
			//debug writeLog(LogType.info, "Removing " ~ to!string(diff) ~ " generators.");
			foreach(int i; 0 .. diff) 
			{
				generators.front.terminate = true;
				generators.removeFront;
			}
		}
		else if(tc > threadCount_) 
		{
			int diff = tc - threadCount_;
			//debug writeLog(LogType.info, "Adding " ~ to!string(diff) ~ " generators.");
			foreach(int i; 0 .. diff) 
			{
				createGenerator();
			}
		}

		next = 0;
	}

	private void createGenerator() 
	{
		NoiseGenerator g = createNG();
		g.setFields(resources, this, seed);
		generators.insertBack(g);
	}

	private int next;

	void generate(NoiseGeneratorOrder c) 
	{
		c.chunk.dataLoadBlocking = true;
		c.chunk.needsData = false;

		generators[next].add(c);
		next++;

		if(next >= threadCount)
			next = 0;
	}
}

abstract class NoiseGenerator 
{
	private shared(bool) terminate_;
	@property bool terminate() { return atomicLoad(terminate_); }
	@property void terminate(bool n) { atomicStore(terminate_, n); }

	private shared(bool) busy_;
	@property bool busy() { return atomicLoad(busy_); }
	@property void busy(bool n) { atomicStore(busy_, n); }

	long seed;

	Resources resources;
	NoiseGeneratorManager manager;

	abstract void add(NoiseGeneratorOrder order);

	void setFields(Resources resources, NoiseGeneratorManager manager, long seed) 
	{
		this.resources = resources;
		this.manager = manager;
		this.seed = seed;
	}

	void setChunkComplete(NoiseGeneratorOrder order) 
	{
		order.chunk.dataLoadCompleted = true;
		order.chunk.dataLoadBlocking = false;

		if(order.fiber is null) return;

		synchronized(manager.completedLock)
			manager.completed.put(order);
	}
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

final class DefaultNoiseGenerator : NoiseGenerator
{
	private Channel!NoiseGeneratorOrder orders;
	private Thread thread;

	override void add(NoiseGeneratorOrder order) { orders.send(order); }

	Moxane moxane;
	private OpenSimplexNoise!float simplex;

	this(Moxane moxane)
	{
		this.moxane = moxane;
		orders = new Channel!NoiseGeneratorOrder;

		raw = VoxelBuffer(overrunDimensions, overrun);
		smootherOutput = VoxelBuffer(overrunDimensions, overrun);
		simplex = new OpenSimplexNoise!float(4);
	}

	~this()
	{
		if(thread !is null && thread.isRunning)
		{
			terminate = true;
			orders.notifyUnsafe;

			thread.join;
			orders.clearUnsafe;
		}
	}

	override void setFields(Resources resources, NoiseGeneratorManager manager, long seed)
	{
		super.setFields(resources, manager, seed);
		assert(thread is null);

		meshes = Meshes.get(resources);
		materials = Materials.get(resources);
		smootherCfg.root = meshes.cube;
		smootherCfg.inv = meshes.invisible;
		smootherCfg.cube = meshes.cube;
		smootherCfg.slope = meshes.slope;
		smootherCfg.tetrahedron = meshes.tetrahedron;
		smootherCfg.antiTetrahedron = meshes.antiTetrahedron;
		smootherCfg.horizontalSlope = meshes.horizontalSlope;

		thread = new Thread(&worker);
		thread.isDaemon = true;
		thread.start;
	}

	private enum int overrun = ChunkData.voxelOffset + 1;
	private enum int overrunDimensions = ChunkData.chunkDimensions + overrun * 2;
	private enum int overrunDimensions3 = overrunDimensions ^^ 3;

	private void worker()
	{
		try
		{
			while(!terminate)
			{
				import std.datetime.stopwatch;
				import std.stdio;
				Maybe!NoiseGeneratorOrder order = orders.await;
				if(!order.isNull)
				{
					StopWatch sw = StopWatch(AutoStart.yes);
					execute(*order.unwrap);
					sw.stop;
					//writeln(sw.peek.total!"nsecs" / 1_000_000f, "msecs");
				}
				else
					return;
			}
		}
		catch(Throwable t)
		{
			import std.stdio;
			writeln(t.info);
		}
	}

	private void execute(NoiseGeneratorOrder order)
	{
		scope(success) setChunkComplete(order);

		if(!order.loadChunk && !order.loadRing) { return; }

		const int s = (order.loadRing ? -overrun : 0) * order.chunk.blockskip;
		const int e = (order.loadRing ? order.chunk.dimensionsProper + overrun : order.chunk.dimensionsProper) * order.chunk.blockskip;

		int premC;

		for(int box = s; box < e; box += order.chunk.blockskip)
		for(int boz = s; boz < e; boz += order.chunk.blockskip)
		{
			if(!order.loadChunk)
				if(box >= 1 && boz >= 1 && box < order.chunk.dimensionsProper - 1 && boz < order.chunk.dimensionsProper - 1)
					continue;

			/+for(int boy = s; boy < e; boy += order.chunk.blockskip)
			{
				Vector3d realPos1 = order.chunkPosition.toVec3dOffset(BlockOffset(box, boy, boz));
				if(realPos1.y <= 0)
					raw.set(box / order.chunk.blockskip, boy / order.chunk.blockskip, boz / order.chunk.blockskip, Voxel(materials.dirt, meshes.cube, 0, 0));
				else
				{
						raw.set(box / order.chunk.blockskip, boy / order.chunk.blockskip, boz / order.chunk.blockskip, Voxel(0, meshes.invisible, 0, 0));
						premC++;
				}
			}+/

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

			float height = archipelago();

			bool outcropping = false;//simplex.eval(realPos.x / 8f + 62, realPos.z / 8f - 763) > 0.5f;
			if(outcropping)
				height += simplex.eval(realPos.x / 4f + 63, realPos.z / 4f + 52) * 32f;

			MaterialID upperMat;
			float mdet = voronoi(Vector2f(realPos.xz) / 8f, simplexSrc).x;
			//upperMat = mdet > 0.5f ? materials.stone : materials.dirt;
			if(mdet < 0.333f) upperMat = materials.dirt;
			else if(mdet >= 0.333f && mdet < 0.666f) upperMat = materials.grass;
			else if(mdet > 0.666f) upperMat = materials.stone;
			upperMat = outcropping ? materials.stone : upperMat;

			for(int boy = s; boy < e; boy += order.chunk.blockskip)
			{
				if(!order.loadChunk)
					if(box >= 1 && boz >= 1 && boy >= 1 && box < order.chunk.dimensionsProper - 1 && boz < order.chunk.dimensionsProper - 1 && boy < order.chunk.dimensionsProper - 1)
						continue;
				Vector3d realPos1 = order.chunkPosition.toVec3dOffset(BlockOffset(box, boy, boz));
				if(realPos1.y <= height)
					raw.set(box / order.chunk.blockskip, boy / order.chunk.blockskip, boz / order.chunk.blockskip, Voxel(realPos1.y < 0.5 && !outcropping ? materials.stone : (upperMat), (outcropping && realPos1.y >= 0.5) ? meshes.cube : meshes.cube, meshes.cube, 0));
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

		runSmoother(order);
		addGrassBlades(order, s, e, premC);

		postProcess(order, premC);
		countAir(order);
	}

	private void addGrassBlades(NoiseGeneratorOrder order, const int s, const int e, ref int premC)
	{
		import squareone.voxelcontent.vegetation;
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
				gv.blockHeightCode = 3;//cast(ubyte)(simplex.eval(realPos.x / 12f + 3265, realPos.z / 12f + 287) * 2f);
				Vector3f colour;
				colour.x = 27 / 255f;
				colour.y = 191 / 255f;
				colour.z = 46 / 255f;
				/+colour.x = 230 / 255f;
				colour.y = 180 / 255f;
				colour.z = 26 / 255f;+/
				gv.colour = colour;

				smootherOutput.set(x, y, z, gv.v);

				/+LeafVoxel lv = LeafVoxel(Voxel(materials.grassBlade, meshes.leaf, 0, 0));
				lv.up = false;
				lv.rotation = cast(FlowerRotation)offset;
				Vector3f colour;
				colour.x = 230 / 255f;
				colour.y = 180 / 255f;
				colour.z = 26 / 255f;
				lv.colour = colour;
				smootherOutput.set(x, y, z, lv.v);+/

				premC--;
			}
		}
	}

	private void runSmoother(NoiseGeneratorOrder o)
	{
		if(true)
			smoother(raw.voxels, smootherOutput.voxels, o.chunk.overrun, o.chunk.dimensionsProper + o.chunk.overrun, overrunDimensions, smootherCfg);
		else
			smootherOutput.dupFrom(raw);
	}

	private void postProcess(NoiseGeneratorOrder order, int premC)
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

	private void countAir(NoiseGeneratorOrder order)
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

	private VoxelBuffer raw;
	private VoxelBuffer smootherOutput;

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
	private Meshes meshes;
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
	private Materials materials;
	private SmootherConfig smootherCfg;
}