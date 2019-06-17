module squareone.terrain.gen.noisegen;

import moxane.core : Moxane, Log;
import squareone.voxel;
import squareone.terrain.gen.simplex;

import containers.cyclicbuffer;
import dlib.math.vector;
import core.thread;
import core.sync.condition;
import core.atomic;

struct NoiseGeneratorOrder
{
	ILoadableVoxelBuffer chunk;
	Vector3d position;
	Fiber fiber;

	private uint toLoad;
	@property bool loadChunk() { return ((toLoad) & 1) == true; }
	@property void loadChunk(bool n) {
		toLoad |= (cast(int)n);
	}

	@property bool loadNeighbour(ChunkNeighbours n) { return ((toLoad >> (cast(int)n + 1)) & 1) == true; }
	@property void loadNeighbour(ChunkNeighbours n, bool e) {
		toLoad |= ((cast(int)e) << (cast(int)n + 1));
	}

	@property bool anyRequiresNoise() { return toLoad > 0; }

	this(ILoadableVoxelBuffer chunk, Vector3d position, Fiber fiber)
	{
		this.chunk = chunk;
		this.position = position;
		this.toLoad = 0;
		this.fiber = fiber;
	}

	void setLoadAll() { toLoad = 0x7FF_FFFF; }
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
			//destroy(generator);
			delete generator;
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

final class DefaultNoiseGenerator : NoiseGenerator 
{
	private Thread thread;

	private struct Meshes 
	{
		ushort invisible,
			cube,
			slope,
			tetrahedron,
			antiTetrahedron,
			horizontalSlope,
			antiObliquePyramid,
			grassMedium;

		static Meshes getMeshes(Resources resources) 
		{
			Meshes meshes;
			meshes.invisible = resources.getMesh("squareOne:voxel:blockMesh:invisible").id;
			meshes.cube = resources.getMesh("squareOne:voxel:blockMesh:cube").id;
			meshes.slope = resources.getMesh("squareOne:voxel:blockMesh:slope").id;
			meshes.tetrahedron = resources.getMesh("squareOne:voxel:blockMesh:tetrahedron").id;
			meshes.antiTetrahedron = resources.getMesh("squareOne:voxel:blockMesh:antitetrahedron").id;
			meshes.horizontalSlope = resources.getMesh("squareOne:voxel:blockMesh:horizontalSlope").id;
			//meshes.grassMedium = resources.getMesh("vegetation_mesh_grass_medium").id;
			return meshes;
		}
	}
	private Meshes meshes;

	private struct Materials {
		ushort air,
			dirt,
			grass,
			flower;
		static Materials getMaterials(Resources resources) {
			Materials materials;
			materials.air = resources.getMaterial("squareOne:voxel:blockMaterial:air").id;
			materials.dirt = resources.getMaterial("squareOne:voxel:blockMaterial:dirt").id;
			materials.grass = resources.getMaterial("squareOne:voxel:blockMaterial:grass").id;
			//materials.flower = resources.getMaterial("vegetation_flower_medium_test").id;
			return materials;
		}
	}
	private Materials materials;

	private Mutex mutex;
	private Condition condition;
	private Object queueSync = new Object;
	private CyclicBuffer!NoiseGeneratorOrder orderQueue;

	Moxane moxane;

	this(Moxane moxane) 
	{
		this.moxane = moxane;
		thread = new Thread(&generator);
		thread.isDaemon = true;

		mutex = new Mutex;
		condition = new Condition(mutex);
	}

	~this()
	{
		try 
		{	
			if(!terminate)
			{
				terminate = true;
				synchronized(mutex)
					condition.notify;
			}
			thread.join;
		}
		catch(Exception e) 
			moxane.services.get!Log().write(Log.Severity.info, "Exception thrown in terminated noise generator thread.");

		while(!orderQueue.empty)
		{
			NoiseGeneratorOrder c = orderQueue.front;
			orderQueue.removeFront;
			c.chunk.dataLoadBlocking = false;
		}
	}

	override void add(NoiseGeneratorOrder order) 
	{
		synchronized(queueSync) 
		{
			busy = true;
			orderQueue.insertBack(order);
			synchronized(mutex)
				condition.notify;
		}
	}

	private NoiseGeneratorOrder getNextFromQueue() 
	{
		bool queueEmpty = false;
		synchronized(queueSync)
			queueEmpty = orderQueue.empty;

		if(queueEmpty)
			synchronized(mutex)
				condition.wait;

		if(terminate) throw new Exception("Abortion.");

		synchronized(queueSync) 
		{
			NoiseGeneratorOrder c = orderQueue.front;
			orderQueue.removeFront;
			return c;
		}
	}

	override void setFields(Resources resources, NoiseGeneratorManager manager, long seed) 
	{
		super.setFields(resources,manager,seed);
		super.seed = seed;
		meshes = Meshes.getMeshes(resources);
		materials = Materials.getMaterials(resources);
		thread.start();
	}

	private void generatorWrap() {
		try generator;
		catch(Throwable e) {
			import std.conv : to;

			//char[] error = "Exception thrown in thread \"" ~ thread.name ~ "\". Contents: " ~ e.message ~ ". Line: " ~ to!string(e.line) ~ "\nStacktrace: " ~ e.info.toString;
			//swriteLog(LogType.error, cast(string)error);
		}
	}

	private void generator() 
	{
		OpenSimplexNoise!float osn = new OpenSimplexNoise!(float)(seed);

		enum sbOffset = 2;
		enum sbDimensions = ChunkData.chunkDimensions + sbOffset * 2;

		source = VoxelBuffer(sbDimensions, sbOffset);
		tempBuffer0 = VoxelBuffer(sbDimensions, sbOffset);
		tempBuffer1 = VoxelBuffer(18, 1);

		import std.datetime.stopwatch;
		StopWatch sw = StopWatch(AutoStart.no);

		while(!terminate) 
		{
			NoiseGeneratorOrder order = getNextFromQueue;

			ILoadableVoxelBuffer chunk = order.chunk;
			busy = true;

			sw.start;

			chunk.airCount = 0;
			chunk.solidCount = 0;

			int premCount = 0;

			const double cdMetres = chunk.dimensionsProper * chunk.voxelScale;

			foreach(int x; -sbOffset .. ChunkData.chunkDimensions + sbOffset) 
			{
				foreach(int z; -sbOffset .. ChunkData.chunkDimensions + sbOffset) 
				{
					//vec3f horizPos = ChunkPosition.blockPosRealCoord(chunk.position, vec3i(x, 0, z));

					Vector3d horizPos = order.position + Vector3d(x * ChunkData.voxelScale, 0, z * ChunkData.voxelScale);

					/*float height = osn.eval(horizPos.x / 256f, horizPos.z / 256f) * 128f;
					height += osn.eval(horizPos.x / 128f, horizPos.z / 128f) * 64f;
					height += osn.eval(horizPos.x / 64f, horizPos.z / 64f) * 32f;
					height += osn.eval(horizPos.x / 4f, horizPos.z / 4f) * 2f;
					height += osn.eval(horizPos.x, horizPos.z) * 0.25f;*/

					float height = osn.eval(horizPos.x / 16f, horizPos.z / 16f) * 8f;
					height += osn.eval(horizPos.x / 64f, horizPos.z / 64f) * 4f;
					height += osn.eval(horizPos.x / 32f, horizPos.z / 32f) * 2f;
					height += osn.eval(horizPos.x / 4f, horizPos.z / 4f) * 1f;
					height += osn.eval(horizPos.x, horizPos.z) * 0.25f;

					//float height = -4f;
					//float oan = osn.eval(horizPos.x / 1.6f - 10f, horizPos.z / 1.6f) * 32f;
					//oan -= 20f;
					//if(oan > -4f)
						//height = oan;

					//double height = 0;
					//height = osn.eval(horizPos.x / 6.4f, horizPos.z / 6.4f) * 0.5f;

					double mat = osn.eval(horizPos.x / 5.6f + 3275, horizPos.z / 5.6f - 734);

					foreach(int y; -sbOffset .. ChunkData.chunkDimensions + sbOffset) 
					{
						const Vector3d blockPos = order.position + Vector3d(x * ChunkData.voxelScale, y * ChunkData.voxelScale, z * ChunkData.voxelScale);
						//vec3f blockPos = ChunkPosition.blockPosRealCoord(chunk.position, vec3i(x, y, z));

						if(blockPos.y <= height) 
						{
							if(mat < 0)
								source.set(x, y, z, Voxel(materials.grass, meshes.cube, 0, 0));
							else
								source.set(x, y, z, Voxel(materials.grass, meshes.cube, 0, 0));
						}
						//if(blockPos.y == height) 
						//	source.set(x, y, z, Voxel(1, 1, 0, 0));
						else 
						{
							source.set(x, y, z, Voxel(0, 0, 0, 0));
							premCount++;
						}
					}
				}
			}

			if(premCount < sbDimensions ^^ 3) 
			{
				processNonAntiTetrahedrons(source, tempBuffer0);
				processAntiTetrahedrons(tempBuffer0, tempBuffer1);

				foreach(int x; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
				{
					foreach(int y; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
					{
						foreach(int z; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
						{
							Voxel voxel = tempBuffer1.get(x, y, z);
							chunk.set(x, y, z, voxel);
						}
					}
				}
			}
			else 
			{
				foreach(int x; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
				{
					foreach(int y; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
					{
						foreach(int z; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
						{
							Voxel voxel = source.get(x, y, z);
							chunk.set(x, y, z, voxel);
						}
					}
				}
			}

			/*foreach(int x; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
			{
			foreach_reverse(int y; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
			{
			foreach(int z; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
			{
			if(y > -ChunkData.voxelOffset) {
			Voxel voxel = chunk.get(x, y, z);
			Voxel below = chunk.get(x, y - 1, z);

			if(voxel.mesh == 0 && below.mesh != 0) {
			vec3d horizPos = order.position + vec3d(x * ChunkData.voxelScale, 0, z * ChunkData.voxelScale);

			float oan = osn.eval(horizPos.x / 1f, horizPos.z / 1f);
			//if(oan < 0.5) continue;

			voxel.mesh = meshes.grassMedium;
			voxel.material = materials.flower;

			import square.one.voxelcon.vegetation.processor;

			FlowerRotation fr;
			if(oan >= 0.5f && oan < 0.55f) fr = FlowerRotation.nz;
			else if(oan >= 0.55f && oan < 0.6f) fr = FlowerRotation.nzpx;
			else if(oan >= 0.6f && oan < 0.65f) fr = FlowerRotation.px;
			else if(oan >= 0.65f && oan < 0.7f) fr = FlowerRotation.pxpz;
			else if(oan >= 0.7f && oan < 0.75f) fr = FlowerRotation.pz;
			else if(oan >= 0.75f && oan < 0.8f) fr = FlowerRotation.nxpz;
			else if(oan >= 0.8f && oan < 0.85f) fr = FlowerRotation.px;
			else fr = FlowerRotation.nxnz;

			float mat0 = osn.eval(horizPos.x / 2.5f + 3275, horizPos.z / 2.5f - 734) * 0.5 + 0.5;
			float mat1 = osn.eval(horizPos.x / 2.5f + 134, horizPos.z / 2.5f - 652) * 0.5 + 0.5;
			float mat2 = osn.eval(horizPos.x / 2.5f + 854, horizPos.z / 2.5f - 1345) * 0.5 + 0.5;

			insertColour(vec3f(mat0, mat1, mat2), &voxel);
			setFlowerRotation(fr, &voxel);

			chunk.set(x, y, z, voxel);
			}
			}
			}
			}
			}*/

			foreach(int x; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
			{
				foreach(int y; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
				{
					foreach(int z; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
					{
						Voxel voxel = chunk.get(x, y, z);
						if(voxel.mesh == meshes.invisible) chunk.airCount = chunk.airCount + 1;
						if(voxel.mesh == meshes.cube) chunk.solidCount = chunk.solidCount + 1;
					}
				}
			}

			setChunkComplete(order);

			sw.stop;
			double nt = sw.peek.total!"nsecs"() / 1_000_000.0;
			if(nt < manager.lowestTime || manager.lowestTime == 0)
				manager.lowestTime = nt;
			if(nt > manager.highestTime || manager.highestTime == 0)
				manager.highestTime = nt;

			if(manager.averageTime == 0)
				manager.averageTime = nt;
			else 
			{
				manager.averageTime += nt;
				manager.averageTime *= 0.5;
			}
			sw.reset;

			busy = false;
		}
	}

	private struct VoxelBuffer 
	{
		Voxel[] voxels;

		int dimensions, offset;

		this(int dimensions, int offset) 
		{
			this.dimensions = dimensions;
			this.offset = offset;
			voxels = new Voxel[dimensions ^^ 3];
		}

		void dupFrom(ref VoxelBuffer other) 
		{
			assert(dimensions == other.dimensions);
			assert(offset == other.offset);
			foreach(int i; 0 .. dimensions ^^ 3)
				voxels[i] = other.voxels[i].dup;
		}

		private int flattenIndex(int x, int y, int z) 
		{
			return x + dimensions * (y + dimensions * z);
		}

		private void throwIfOutOfBounds(int x, int y, int z) 
		{
			if(x < -offset || y < -offset || z < -offset || x >= dimensions + offset || y >= dimensions + offset || z >= dimensions + offset)
				throw new Exception("Out of bounds.");
		}

		Voxel get(int x, int y, int z) 
		{
			debug throwIfOutOfBounds(x, y, z);
			return voxels[flattenIndex(x + offset, y + offset, z + offset)];
		}

		void set(int x, int y, int z, Voxel voxel) 
		{
			debug throwIfOutOfBounds(x, y, z);
			voxels[flattenIndex(x + offset, y + offset, z + offset)] = voxel;
		}
	}

	private VoxelBuffer source;
	private VoxelBuffer tempBuffer0;
	private VoxelBuffer tempBuffer1;

	void processNonAntiTetrahedrons(ref VoxelBuffer source, ref VoxelBuffer tempBuffer0) 
	{
		tempBuffer0.dupFrom(source);

		foreach(int x; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
			foreach(int y; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset)
				foreach(int z; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
				{
					Voxel voxel = source.get(x, y, z);

					if(voxel.mesh == 0) 
					{
						//tempBuffer0.set(x, y, z, voxel);
						continue;
					}

					Voxel nx = source.get(x - 1, y, z);
					Voxel px = source.get(x + 1, y, z);
					Voxel ny = source.get(x, y - 1, z);
					Voxel py = source.get(x, y + 1, z);
					Voxel nz = source.get(x, y, z - 1);
					Voxel pz = source.get(x, y, z + 1);

					Voxel nxnz = source.get(x - 1, y, z - 1);
					Voxel nxpz = source.get(x - 1, y, z + 1);
					Voxel pxnz = source.get(x + 1, y, z - 1);
					Voxel pxpz = source.get(x + 1, y, z + 1);

					Voxel pynz = source.get(x, y + 1, z - 1);
					Voxel pypz = source.get(x, y + 1, z + 1);
					Voxel nxpy = source.get(x - 1, y + 1, z);
					Voxel pxpy = source.get(x + 1, y + 1, z);

					bool setDef = false;

					if(ny.mesh == 0)
						setDef = true;
					else 
					{
						if(nx.mesh != 0 && px.mesh == 0 && nz.mesh != 0 && pz.mesh != 0 && py.mesh == 0) 
							tempBuffer0.set(x, y, z, Voxel(voxel.material, 2, voxel.materialData, 0));
						else if(px.mesh != 0 && nx.mesh == 0 && nz.mesh != 0 && pz.mesh != 0 && py.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.slope, voxel.materialData, 2));
						else if(nz.mesh != 0 && pz.mesh == 0 && nx.mesh != 0 && px.mesh != 0 && py.mesh == 0) 
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.slope, voxel.materialData, 1));
						else if(pz.mesh != 0 && nz.mesh == 0 && nx.mesh != 0 && px.mesh != 0 && py.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.slope, voxel.materialData, 3));

						else if(nx.mesh != 0 && nz.mesh != 0 && px.mesh == 0 && pz.mesh == 0 && py.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.tetrahedron, voxel.materialData, 0));

						else if(px.mesh != 0 && nz.mesh != 0 && nx.mesh == 0 && pz.mesh == 0 && py.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.tetrahedron, voxel.materialData, 1));

						else if(px.mesh != 0 && pz.mesh != 0 && nx.mesh == 0 && nz.mesh == 0 && py.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.tetrahedron, voxel.materialData, 2));

						else if(nx.mesh != 0 && pz.mesh != 0 && px.mesh == 0 && nz.mesh == 0 && py.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.tetrahedron, voxel.materialData, 3));

						else if(nx.mesh != 0 && pz.mesh != 0 && px.mesh == 0 && nz.mesh == 0 && pxnz.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.horizontalSlope, voxel.materialData, 0));
						else if(nx.mesh != 0 && nz.mesh != 0 && px.mesh == 0 && pz.mesh == 0 && pxpz.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.horizontalSlope, voxel.materialData, 1));
						else if(px.mesh != 0 && nz.mesh != 0 && nx.mesh == 0 && pz.mesh == 0 && nxpz.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.horizontalSlope, voxel.materialData, 2));
						else if(px.mesh != 0 && pz.mesh != 0 && nx.mesh == 0 && nz.mesh == 0 && nxnz.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.horizontalSlope, voxel.materialData, 3));

						else setDef = true;
					}

					if(setDef)
						tempBuffer0.set(x, y, z, voxel);
				}
	}

	void processAntiTetrahedrons(ref VoxelBuffer tempBuffer0, ref VoxelBuffer tempBuffer1) 
	{
		foreach(int x; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset)
		foreach(int y; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset)
		foreach(int z; -ChunkData.voxelOffset .. ChunkData.chunkDimensions + ChunkData.voxelOffset) 
		{
			Voxel voxel = tempBuffer0.get(x, y, z);

			if(voxel.mesh == 0) 
			{
				tempBuffer1.set(x, y, z, voxel);
				continue;
			}

			bool setDef = false;

			Voxel nx = tempBuffer0.get(x - 1, y, z);
			Voxel px = tempBuffer0.get(x + 1, y, z);
			Voxel ny = tempBuffer0.get(x, y - 1, z);
			Voxel py = tempBuffer0.get(x, y + 1, z);
			Voxel nz = tempBuffer0.get(x, y, z - 1);
			Voxel pz = tempBuffer0.get(x, y, z + 1);

			Voxel nxnz = tempBuffer0.get(x - 1, y, z - 1);
			Voxel nxpz = tempBuffer0.get(x - 1, y, z + 1);
			Voxel pxnz = tempBuffer0.get(x + 1, y, z - 1);
			Voxel pxpz = tempBuffer0.get(x + 1, y, z + 1);

			if(ny.mesh == 0)
				setDef = true;
			else 
			{
				if(nx.mesh != 0 && nz.mesh != 0 && px.mesh != 0 && pz.mesh != 0) 
				{
					if(pxpz.mesh == 0 && !(px.mesh == meshes.cube || pz.mesh == meshes.cube))
						tempBuffer1.set(x, y, z, Voxel(voxel.material, meshes.antiTetrahedron, voxel.materialData, 0));
					else if(nxpz.mesh == 0 && !(nx.mesh == meshes.cube || pz.mesh == meshes.cube))
						tempBuffer1.set(x, y, z, Voxel(voxel.material, meshes.antiTetrahedron, voxel.materialData, 1));
					else if(nxnz.mesh == 0 && !(nx.mesh == meshes.cube || nz.mesh == meshes.cube))
						tempBuffer1.set(x, y, z, Voxel(voxel.material, meshes.antiTetrahedron, voxel.materialData, 2));
					else if(pxnz.mesh == 0 && !(px.mesh == meshes.cube || nz.mesh == meshes.cube))
						tempBuffer1.set(x, y, z, Voxel(voxel.material, meshes.antiTetrahedron, voxel.materialData, 3));
					else setDef = true;
				}
				else if(voxel.mesh == meshes.cube && nx.mesh == meshes.cube && px.mesh != meshes.cube && nz.mesh == 0 && pz.mesh == meshes.cube && py.mesh != meshes.cube)
					tempBuffer1.set(x, y, z, Voxel(voxel.material, meshes.antiTetrahedron, voxel.materialData, 3));
				else if(voxel.mesh == meshes.cube && nx.mesh == meshes.cube && px.mesh == 0 && nz.mesh != meshes.cube && pz.mesh == meshes.cube && py.mesh != meshes.cube)
					tempBuffer1.set(x, y, z, Voxel(voxel.material, meshes.antiTetrahedron, voxel.materialData, 3));
				else if(voxel.mesh == meshes.cube && nx.mesh == meshes.cube && px.mesh == 0 && nz.mesh == meshes.cube && pz.mesh != meshes.cube && py.mesh != meshes.cube)
					tempBuffer1.set(x, y, z, Voxel(voxel.material, meshes.antiTetrahedron, voxel.materialData, 0));
				else if(voxel.mesh == meshes.cube && nx.mesh == meshes.cube && px.mesh != meshes.cube && nz.mesh == meshes.cube && pz.mesh == 0 && py.mesh != meshes.cube)
					tempBuffer1.set(x, y, z, Voxel(voxel.material, meshes.antiTetrahedron, voxel.materialData, 0));
				else if(voxel.mesh == meshes.cube && nx.mesh == 0 && px.mesh == meshes.cube && nz.mesh != meshes.cube && pz.mesh == meshes.cube && py.mesh != meshes.cube)
					tempBuffer1.set(x, y, z, Voxel(voxel.material, meshes.antiTetrahedron, voxel.materialData, 2));
				else if(voxel.mesh == meshes.cube && nx.mesh != meshes.cube && px.mesh == meshes.cube && nz.mesh == 0 && pz.mesh == meshes.cube && py.mesh != meshes.cube)
					tempBuffer1.set(x, y, z, Voxel(voxel.material, meshes.antiTetrahedron, voxel.materialData, 2));
				else if(voxel.mesh == meshes.cube && nx.mesh == 0 && px.mesh == meshes.cube && nz.mesh == meshes.cube && pz.mesh != meshes.cube && py.mesh != meshes.cube)
					tempBuffer1.set(x, y, z, Voxel(voxel.material, meshes.antiTetrahedron, voxel.materialData, 1));
				else if(voxel.mesh == meshes.cube && nx.mesh != meshes.cube && px.mesh == meshes.cube && nz.mesh == meshes.cube && pz.mesh == 0 && py.mesh != meshes.cube)
					tempBuffer1.set(x, y, z, Voxel(voxel.material, meshes.antiTetrahedron, voxel.materialData, 1));
				else setDef = true;
			}

			if(setDef)
				tempBuffer1.set(x, y, z, voxel);
		}
	}
}
