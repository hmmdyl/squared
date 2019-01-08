module square.one.terrain.basic.manager;

import moxana.graphics.rendercontext;
import moxana.graphics.rh;
import moxana.graphics.frustum;
import moxana.utils.event;

import square.one.terrain.basic.chunk;
import square.one.terrain.noisegen;
import square.one.terrain.resources;
import square.one.terrain.basic.rle;

import square.one.utils.math : flattenIndex;
import square.one.utils.floor : ifloordiv;

import containers.hashset;
import containers.unrolledlist;
import containers.dynamicarray;
import std.experimental.allocator.mallocator;

import gfm.math;

import std.math;
import std.conv : to;
import std.file;
import std.datetime.stopwatch;
import std.parallelism;

struct BasicTmSettings 
{
    vec3i addRange;
	vec3i addRangeExtended;
    vec3i removeRange;
    NoiseGeneratorManager.createNGDel createNg;
    Resources resources;

	string worldSavesDir;	/// directory that stores worlds
	string worldDir; /// sanitised world name
	string worldName;	/// name of the world

	static BasicTmSettings createDefault(Resources r, string worldSavesDir, string worldDir, string worldName)
	{
		BasicTmSettings tm;
		tm.addRange = vec3i(5);
		tm.addRangeExtended = vec3i(20);
		tm.removeRange = vec3i(4, 6, 4);
		tm.createNg = () { return new DefaultNoiseGenerator(); };
		tm.resources = r;
		tm.worldSavesDir = worldSavesDir;
		tm.worldDir = worldDir;
		tm.worldName = worldName;
		return tm;
	}
}

/// set a block on the terrain
struct SetBlockCommand 
{
	long x; /// block position    
	long y; /// ditto    
	long z; /// ditto    
	Voxel voxel; /// the new voxel

	bool forceLoad; /// force the engine to load the chunk if not already

    this(long x, long y, long z, Voxel voxel, bool forceLoad = false)
    {
        this.x = x;
        this.y = y;
        this.z = z;
        this.voxel = voxel;
        this.forceLoad = forceLoad;
    }
}

struct RequestPhysicsForChunkCommand
{

}

private enum int chunksPerRegionAxis = 4;
private enum int chunksPerRegionCubed = chunksPerRegionAxis ^^ 3;

private final class WorldSaveManager
{
	private class VoxelBuffer 
	{
		enum int lifeTimeSecondsBase = 10;

		Voxel[] voxels;
		int numTimesAccessed;
		StopWatch life;

		this(int numVoxels)
		{
			auto numBytes = numVoxels * Voxel.sizeof;
			voxels = cast(Voxel[])Mallocator.instance.allocate(numBytes);
			life = StopWatch(AutoStart.yes);
		}

		@property bool isOverTime() { return life.peek().total!"seconds"() > lifeTimeSecondsBase * numTimesAccessed; }

		~this()
		{
			Mallocator.instance.deallocate(voxels);
			voxels = null;
		}
	}

	NoiseGeneratorManager noiseGenerator;

	private VoxelBuffer[ChunkPosition] buffers;
	private HashSet!vec3i outGoingRegions;
	BasicChunk[ChunkPosition]* activeChunks;

	const string worldSavesDir;
	const string worldDir;
	const string worldName;

	this(NoiseGeneratorManager noiseGenerator, BasicChunk[ChunkPosition]* activeChunks, string worldSavesDir, string worldDir, string worldName)
	{
		this.noiseGenerator = noiseGenerator;
		this.activeChunks = activeChunks;
		this.worldSavesDir = worldSavesDir;
		this.worldDir = worldDir;
		this.worldName = worldName;
	}

	private string composeRegionName(vec3i r)
	{
		string regionName;
		regionName ~= to!string(r.x);
		regionName ~= '_';
		regionName ~= to!string(r.y);
		regionName ~= '_';
		regionName ~= to!string(r.z);		
		regionName ~= ".sqr";
		return regionName;
	}

	private bool regionExists(vec3i r, out string fin)
	{
		string regionName = composeRegionName(r);
		import std.path : buildPath;
		fin = buildPath(worldSavesDir, worldDir, "regions", regionName);
		return exists(fin);
	}

	private bool chunkInRegionExists(vec3i region, ChunkPosition internal, out string file)
	{
		bool regionFileExists = regionExists(region, file);
		if(!regionFileExists) return false;

		import std.file : read;
		ulong header;
		ubyte[] headerArr = (*cast(ubyte[ulong.sizeof]*)&header);
		headerArr[0..$] = cast(ubyte[])read(file, ulong.sizeof)[0 .. ulong.sizeof];

		int index, s, e;
		getIndices(internal.toVec3i(), index, s, e);

		return ((header >> index) & 1) == 1;
	}

	private void getIndices(vec3i cpInternal, 
		out int index, out int start, out int end)
	{
		index = flattenIndex(cpInternal.x, cpInternal.y, cpInternal.z, chunksPerRegionAxis);
		start = cast(int)(ChunkData.chunkDimensions * Voxel.sizeof * index + ulong.sizeof);
		end = cast(int)(start + ChunkData.chunkDimensions * Voxel.sizeof);
	} 

	private enum int regionFileSize = chunksPerRegionCubed * ChunkData.chunkDimensionsCubed * Voxel.sizeof + ulong.sizeof;

	private vec3i getRegion(ChunkPosition cp, out ChunkPosition internal)
	{
		const int rx = ifloordiv(cp.x, chunksPerRegionAxis);
		const int ry = ifloordiv(cp.y, chunksPerRegionAxis);
		const int rz = ifloordiv(cp.z, chunksPerRegionAxis);

		internal.x = cp.x - (rx * chunksPerRegionAxis);
		internal.y = cp.y - (ry * chunksPerRegionAxis);
		internal.z = cp.z - (rz * chunksPerRegionAxis);

		return vec3i(rx, ry, rz);
	}

	void loadChunk(BasicChunk* chunk)
	{
		chunk.chunk.needsData = false;
		chunk.chunk.dataLoadBlocking = true;

		ChunkPosition internal;
		vec3i region = getRegion(chunk.position, internal);

		ChunkPosition[26] neighbours;
		foreach(int c; 0 .. cast(int)ChunkNeighbours.last)
		{
			ChunkNeighbours n = cast(ChunkNeighbours)c;
			vec3i o = chunkNeighbourToOffset(n);
			neighbours[c] = ChunkPosition(chunk.position.x + o.x, chunk.position.y + o.y, chunk.position.z + o.z);
		}
		vec3i[26] regionsOfNeighbours;
		ChunkPosition[26] internalNeighbours;
		foreach(int c, ChunkPosition cp; neighbours)
			regionsOfNeighbours[c] = getRegion(neighbours[c], internalNeighbours[c]);

		NoiseGeneratorOrder order = NoiseGeneratorOrder(chunk.chunk, chunk.position.toVec3d);

		vec3i[27] uniqueRegions;
		int numUniqueRegions;
		uniqueRegions[0] = region;
		foreach(vec3i o; regionsOfNeighbours)
		{
			bool isFound;
			foreach(vec3i o2; uniqueRegions)
				if(o2 == o) 
					isFound = true;

			if(isFound)
				continue;

			uniqueRegions[numUniqueRegions++] = o;
		}

		foreach(vec3i ron; uniqueRegions)
		{
			string regionFile;
			const bool regEx = regionExists(ron, regionFile);	
			if(!regEx) continue;

			ubyte[regionFileSize] raw = cast(ubyte[])read(regionFile, regionFileSize);

			ulong header;
			ubyte[] headerArr = (*cast(ubyte[ulong.sizeof]*)&header);
			headerArr[0..$] = raw[0..ulong.sizeof];

			foreach(int cx; 0 .. chunksPerRegionAxis)
			foreach(int cy; 0 .. chunksPerRegionAxis)
			foreach(int cz; 0 .. chunksPerRegionAxis)
			{
				const int c = flattenIndex(cx, cy, cz, chunksPerRegionAxis);
				const bool chunkExistsInFile = ((header >> c) & 1) == true;
				if(chunkExistsInFile)
				{
					int cIndex, cfStart, cfEnd;
					getIndices(internalNeighbours[c].toVec3i(), cIndex, cfStart, cfEnd);

					const ChunkPosition cp = ChunkPosition(ron.x * 4 + cx, ron.y * 4 + cy, ron.z * 4 + cz);
					if((cp in buffers) !is null)
						continue;

					VoxelBuffer buffer = new VoxelBuffer(ChunkData.chunkDimensionsCubed);
					
					for(int v = 0, i = cfStart; v < ChunkData.chunkDimensionsCubed; v++, i += Voxel.sizeof)
					{
						Voxel tv;
						ubyte[] tvArr = (*cast(ubyte[Voxel.sizeof]*)&tv);
						tvArr[0..$] = raw[i..(i + Voxel.sizeof)];

						buffer.voxels[v] = tv;
					}

					buffers[cp] = buffer;
				}
			}
		}		

		bool[26] neighboursThatMustBeGeneratedFromNoise;
		foreach(int i, ChunkPosition p; neighbours)
			neighboursThatMustBeGeneratedFromNoise[i] = (p in buffers) is null;
		const bool chunkMustBeGeneratedFromNoise = (chunk.position in buffers) is null;

		if(chunkMustBeGeneratedFromNoise)
			order.loadChunk = true;
		else
		{
			VoxelBuffer* buffer = chunk.position in buffers;
			foreach(int x; 0 .. chunk.chunk.dimensionsProper)
			foreach(int y; 0 .. chunk.chunk.dimensionsProper)
			foreach(int z; 0 .. chunk.chunk.dimensionsProper)
			{
				chunk.chunk.set(x, y, z, buffer.voxels[flattenIndex(x, y, z, chunk.chunk.dimensionsProper)]);
			}
		}

		foreach(int i; 0 .. cast(int)ChunkNeighbours.last)
		{
			if(neighboursThatMustBeGeneratedFromNoise[i])
				order.loadNeighbour(cast(ChunkNeighbours)i, true);
			else
			{
				BasicChunk* bcn = neighbours[i] in *activeChunks;
				VoxelBuffer* buffer;
				if(bcn is null)
				{
					buffer = neighbours[i] in buffers;
					buffer.numTimesAccessed++;
				}

				assert(bcn !is null || buffer !is null);
				
				const vec3i cnOffset = chunkNeighbourToOffset(cast(ChunkNeighbours)i);
				
				const vec3i neighbourVoxelCoord = vec3i(
					cnOffset.x < 0 ? ChunkData.chunkDimensions - 1 : 0,
					cnOffset.y < 0 ? ChunkData.chunkDimensions - 1 : 0,
					cnOffset.z < 0 ? ChunkData.chunkDimensions - 1 : 0
				);

				const bool[3] toIterate = [
					cnOffset.x == 0,
					cnOffset.y == 0,
					cnOffset.z == 0
				];

				foreach(int vx; neighbourVoxelCoord.x .. (toIterate[0] ? ChunkData.chunkDimensions : neighbourVoxelCoord.x + 1))
				foreach(int vy; neighbourVoxelCoord.y .. (toIterate[1] ? ChunkData.chunkDimensions : neighbourVoxelCoord.y + 1))
				foreach(int vz; neighbourVoxelCoord.z .. (toIterate[2] ? ChunkData.chunkDimensions : neighbourVoxelCoord.z + 1))
				{
					const int ix = toIterate[0] ? vx : (vx == ChunkData.chunkDimensions - 1 ? vx - ChunkData.chunkDimensions : ChunkData.chunkDimensions - vx);
					const int iy = toIterate[1] ? vy : (vy == ChunkData.chunkDimensions - 1 ? vy - ChunkData.chunkDimensions : ChunkData.chunkDimensions - vy);
					const int iz = toIterate[2] ? vz : (vz == ChunkData.chunkDimensions - 1 ? vz - ChunkData.chunkDimensions : ChunkData.chunkDimensions - vz);					

					if(bcn !is null)
						chunk.chunk.set(ix, iy, iz, bcn.chunk.get(vx, vy, vz));
					else
						chunk.chunk.set(ix, iy, iz, buffer.voxels[flattenIndex(vx, vy, vz, chunk.chunk.dimensionsProper)]);
				}
			}
		}

		if(order.anyRequiresNoise)
			noiseGenerator.generate(order);
		else
		{
			chunk.chunk.dataLoadCompleted = true;
			chunk.chunk.dataLoadBlocking = false;
		}
	}

	void saveChunk(BasicChunk* chunk)
	{
		// TODO: implement caching 
		ChunkPosition internal;
		vec3i region = getRegion(chunk.position, internal);

		string filename;
		bool regionFileExists = regionExists(region, filename);

		ubyte[regionFileSize] raw;
		raw[] = 0;

		ulong getHeader()
		{
			ulong header;
			ubyte[] headerArr = (*cast(ubyte[ulong.sizeof]*)&header);
			headerArr[0..$] = raw[0..ulong.sizeof];
			return header;
		}

		void writeToHeader(int n, bool state)
		{
			ulong header = getHeader();
			if(state) header |= (1 << n);
			else header = header & ~(1 << n);

			ubyte[] headerArr = (*cast(ubyte[ulong.sizeof]*)&header);
			foreach(int x; 0 .. ulong.sizeof)
				raw[x] = headerArr[x];
		}

		bool readFromHeader(int n)
		{ return ((getHeader() >> n) & 1) == true; }

		if(regionFileExists)
			raw = cast(ubyte[])read(filename);

		int index, start, end;
		getIndices(internal.toVec3i, index, start, end);

		writeToHeader(index, true);

		int voxelC = 0;
		foreach(int x; 0 .. ChunkData.chunkDimensions)
		{
			foreach(int y; 0 .. ChunkData.chunkDimensions)
			{
				foreach(int z; 0 .. ChunkData.chunkDimensions)
				{
					Voxel v = chunk.chunk.get(x, y, z);
					ubyte[] vArr = (*cast(ubyte[Voxel.sizeof]*)&v);
					foreach(uint vByte; 0 .. Voxel.sizeof)
					{
						const int point = start + voxelC * cast(int)Voxel.sizeof + vByte;
						raw[point] = vArr[vByte];
					}

					voxelC++;
				}
			}
		}

		write(filename, cast(void[])raw);
	}

	void saveChunkCached(BasicChunk* chunk)
	{
		VoxelBuffer* bufferGetter = chunk.position in buffers;
		bool isAbsentFromBuffers = bufferGetter is null;
		VoxelBuffer newBuffer;

		if(isAbsentFromBuffers) newBuffer = new VoxelBuffer(ChunkData.chunkDimensionsCubed);
		else newBuffer = *bufferGetter;
		newBuffer.numTimesAccessed++;

		foreach(int x; 0 .. ChunkData.chunkDimensions)
		{
			foreach(int y; 0 .. ChunkData.chunkDimensions)
			{
				foreach(int z; 0 .. ChunkData.chunkDimensions)
				{
					Voxel v = chunk.chunk.get(x, y, z);
					newBuffer.voxels[flattenIndex(x, y, z, ChunkData.chunkDimensions)] = v;
				}
			}
		}

		if(isAbsentFromBuffers)
			buffers[chunk.position] = newBuffer;

		ChunkPosition internal;
		vec3i region = getRegion(chunk.position, internal);
		if(!outGoingRegions.contains(region))
			outGoingRegions.insert(region);
	}

	void writeChunks()
	{
		foreach(vec3i region; outGoingRegions)
		{
			ChunkPosition[chunksPerRegionCubed] inRegions;
			vec3i[chunksPerRegionCubed] internalCoords;
			int inRegionsCount;
			foreach(int ix; 0 .. chunksPerRegionAxis)
			{
				foreach(int iy; 0 .. chunksPerRegionAxis)
				{
					foreach(int iz; 0 .. chunksPerRegionAxis)
					{
						internalCoords[inRegionsCount] = vec3i(ix, iy, iz);
						ChunkPosition cp;
						cp.x = region.x * chunksPerRegionAxis + ix;
						cp.y = region.y * chunksPerRegionAxis + iy;
						cp.z = region.z * chunksPerRegionAxis + iz;
						inRegions[inRegionsCount] = cp;
						inRegionsCount++;
					}
				}
			}

			ubyte[regionFileSize] finalRaw;
			ubyte[regionFileSize] loadedRaw;
			string filename;
			bool doesRegionExist = regionExists(region, filename);
			if(doesRegionExist)
				loadedRaw = cast(ubyte[])read(filename);
		
			ulong finalHeader;
			ulong loadedHeader;
			if(doesRegionExist)
				loadedHeader = interpretHeader(loadedRaw);

			foreach(int i; 0 .. chunksPerRegionCubed)
			{
				ChunkPosition pos = inRegions[i];

				enum Source 
				{
					none,
					fromFile,
					fromBuffer
				}

				Source source = (pos in buffers) ? Source.fromBuffer :
					(doesRegionExist ? (readFromHeader(loadedHeader, i) ? 
						Source.fromFile : Source.none) : Source.none);

				writeToHeader(finalHeader, i, source != Source.none);

				int index, start, end;
				getIndices(internalCoords[i], index, start, end);

				if(source == Source.none)
					finalRaw[start .. end] = 0;
				else if(source == Source.fromBuffer)
				{
					VoxelBuffer* buffer = inRegions[i] in buffers;
					assert(buffer !is null);

					int voxelCounter = 0;
					foreach(int x; 0 .. ChunkData.chunkDimensions)
					{
						foreach(int y; 0 .. ChunkData.chunkDimensions)
						{
							foreach(int z; 0 .. ChunkData.chunkDimensions)
							{
								Voxel v = buffer.voxels[flattenIndex(x, y, z, ChunkData.chunkDimensions)];
								ubyte[] vArr = (*cast(ubyte[Voxel.sizeof]*)&v);
								int low = start + voxelCounter * cast(int)Voxel.sizeof;
								finalRaw[low .. low + Voxel.sizeof] = vArr[0 .. $];

								voxelCounter++;
							}
						}
					}
				}
				else
				{
					finalRaw[start .. end] = loadedRaw[start .. end];
				}
			}
		

			write(filename, cast(void[])finalRaw);
		}

		outGoingRegions.clear();
	}

	private ulong interpretHeader(ref ubyte[regionFileSize] raw)
	{
		ulong header;
		ubyte[] headerArr = (*cast(ubyte[ulong.sizeof]*)&header);
		headerArr[0..$] = raw[0 .. ulong.sizeof];
		return header;
	}

	private void writeHeader(ref ubyte[regionFileSize] raw, ulong header)
	{
		ubyte[] headerArr = (*cast(ubyte[ulong.sizeof]*)&header);
		raw[0 .. ulong.sizeof] = headerArr[0 .. $];
	}

	private void writeToHeader(ref ulong header, int n, bool state)
	{
		if(state) header |= (1 << n);
		else header = header & ~(1 << n);
	}

	private bool readFromHeader(ulong header, int n)
	{
		return ((header >> n) & 1) == true;
	}
}

final class BasicTerrainRenderer : IRenderHandler
{
	BasicTerrainManager basicTerrainManager;
	
	this(BasicTerrainManager basicTerrainManager)
	{
		this.basicTerrainManager = basicTerrainManager;
	}

	private int renderedInFrame_;
	private int shadowsInFrame_;
	@property int renderedInFrame() const { return renderedInFrame_; }
	@property int shadowsInFrame() const { return shadowsInFrame_; }

	void renderPostPhysical(RenderContext rc, ref LocalRenderContext lrc) { renderPhysical(rc, lrc); }
	void ui(RenderContext rc) {}
	
	void shadowDepthMapPass(RenderContext rc, ref LocalRenderContext lrc)
	{
		shadowsInFrame_ = 0;

		foreach(int procID; 0 .. basicTerrainManager.resources.processorCount)
		{
			IProcessor processor = basicTerrainManager.resources.getProcessor(procID);
			processor.prepareRenderShadow(rc);
			
			foreach(ref BasicChunk chunk; basicTerrainManager.chunksTerrain)
			{
				processor.renderShadow(chunk.chunk, lrc);
				renderedInFrame_++;
			}
			
			processor.endRenderShadow();
		}
	}
	
	void renderPhysical(RenderContext rc, ref LocalRenderContext lrc)
	{
		renderedInFrame_ = 0;

		mat4f vp = lrc.perspective.matrix * lrc.view;
		SqFrustum!float f = SqFrustum!float(vp.transposed());

		foreach(int procID; 0 .. basicTerrainManager.resources.processorCount)
		{
			IProcessor processor = basicTerrainManager.resources.getProcessor(procID);
			processor.prepareRender(rc);

			foreach(ref BasicChunk chunk; basicTerrainManager.chunksTerrain)
			{
				//if(f.containsSphere(chunk.position.toVec3f() + vec3f(2), 5.66))
				{
					processor.render(chunk.chunk, lrc);
					renderedInFrame_++;
				}
			}

			processor.endRender();
		}
	}
}

final class BasicTerrainManager
{
	enum ChunkState
	{
		notLoaded,
		hibernated,
		active
	}

    private BasicChunk[ChunkPosition] chunksTerrain;
	private ChunkState[ChunkPosition] chunkHoles;

	private enum commandQueueSize = 256;
	private DynamicArray!SetBlockCommand setBlockCommands;

    private BasicTmSettings settings_;
	@property BasicTmSettings settings() { return settings_; }
	Resources resources;

    vec3f cameraPosition;

	private WorldSaveManager worldSaveManager;
	NoiseGeneratorManager noiseGeneratorManager;

	private StopWatch addExtensionResortSw;
	private bool isExtensionCacheSorted;
	private ChunkPosition[] extensionChunkPositionCache;

	private TaskPool localTaskPool;

	int chunksAdded;
	int chunksHibernated;
	int chunksRemoved;

	@property int chunksActive() const { return cast(int)chunksTerrain.length; }
	@property int chunksActiveOrHibernated() const { return cast(int)chunkHoles.length; }

    this(BasicTmSettings s)
    {
        settings_ = s;
		resources = s.resources;
		resources.finaliseResources;

		noiseGeneratorManager = new NoiseGeneratorManager(resources, 1, s.createNg, 0);

		extensionChunkPositionCache = new ChunkPosition[(s.addRangeExtended.x * 2 + 1) * (s.addRangeExtended.y * 2 + 1) * (s.addRangeExtended.z * 2 + 1)];

		localTaskPool = new TaskPool(1);

		setBlockCommands.reserve(256);
    }

	void addSetBlockCommand(SetBlockCommand comm) { setBlockCommands.insert(comm); }

    void update()
    {
		const ChunkPosition cp = ChunkPosition.fromVec3f(cameraPosition);
		//addChunks(cp);

		addChunksLocal(cp);
		addChunksExtension(cp);

		foreach(ref BasicChunk chunk; chunksTerrain)
		{
			manageChunkState(chunk);
			//removeChunkHandler(chunk, cp);
		}
    }

	private void addChunksLocal(const ChunkPosition cp)
	{
		vec3i lower = vec3i(
			cp.x - settings_.addRange.x,
			cp.y - settings_.addRange.y,
			cp.z - settings_.addRange.z
		);
		vec3i upper = vec3i(
			cp.x + settings_.addRange.x,
			cp.y + settings_.addRange.y,
			cp.z + settings_.addRange.z
		);

		for(int x = lower.x; x < upper.x; x++)
		{
			for(int y = lower.y; y < upper.y; y++)
			{
				for(int z = lower.z; z < upper.z; z++)
				{
					auto newCp = ChunkPosition(x, y, z);

					ChunkState* getter = newCp in chunkHoles;
					//ChunkState g = 
					bool doAdd = getter is null || *getter == ChunkState.notLoaded;

					//BasicChunk* getter = newCp in chunksTerrain;
					if(doAdd)
					{
						auto c = new Chunk(settings_.resources);
						c.initialise();
						c.needsData = true;
						c.lod = 0;
						c.blockskip = 1;
						auto chunk = BasicChunk(c, newCp);
						chunksTerrain[newCp] = chunk;
						chunkHoles[newCp] = ChunkState.active;

						chunksAdded++;
					}
					else
					{

						//pendingRemove = false;
					}
				}
			}
		}
	}

	private void addChunksExtension(const ChunkPosition cam)
	{
		bool doSort;

		if(!addExtensionResortSw.running)
		{
			addExtensionResortSw.start();
			doSort = true;
		}

		if(addExtensionResortSw.peek().total!"msecs"() >= 300)
		{
			addExtensionResortSw.reset();
			addExtensionResortSw.start();
			doSort = true;
		}

		if(doSort)
		{
			isExtensionCacheSorted = false;

			vec3i lower = vec3i(
				cam.x - settings_.addRangeExtended.x,
				cam.y - settings_.addRangeExtended.y,
				cam.z - settings_.addRangeExtended.z
			);
			vec3i upper = vec3i(
				cam.x + settings_.addRangeExtended.x,
				cam.y + settings_.addRangeExtended.y,
				cam.z + settings_.addRangeExtended.z
			);

			int c;
			for(int x = lower.x; x < upper.x; x++)
				for(int y = lower.y; y < upper.y; y++)
					for(int z = lower.z; z < upper.z; z++)
						extensionChunkPositionCache[c++] = ChunkPosition(x, y, z);

			auto cdCmp(ChunkPosition x, ChunkPosition y)
			{
				float caml = cam.toVec3f.length;
				float x1 = x.toVec3f.length - caml;
				float y1 = y.toVec3f.length - caml;
				return x1 < y1;
			}

			void myTask(ChunkPosition[] cache)
			{
				import std.algorithm.sorting;
				sort!cdCmp(cache);
				isExtensionCacheSorted = true;
			}

			auto sortTask = task(&myTask, extensionChunkPositionCache);
			localTaskPool.put(sortTask);
		}

		if(!isExtensionCacheSorted)
			return;

		int doAddNum;

		foreach(ChunkPosition cp; extensionChunkPositionCache)
		{
			ChunkState* getter = cp in chunkHoles;
			bool doAdd = getter is null || *getter == ChunkState.notLoaded;

			if(doAdd)
			{
				if(doAddNum > 4) return;

				auto c = new Chunk(settings_.resources);
				c.initialise();
				c.needsData = true;
				c.lod = 0;
				c.blockskip = 1;
				auto chunk = BasicChunk(c, cp);
				chunksTerrain[cp] = chunk;
				chunkHoles[cp] = ChunkState.active;

				chunksAdded++;

				doAddNum++;
			}
		}
	}

	private void removeChunkHandler(ref BasicChunk chunk, const ChunkPosition camera)
	{
		if(!isChunkInBounds(camera, chunk.position))
		{
			if(chunk.chunk.needsData || chunk.chunk.dataLoadBlocking || chunk.chunk.dataLoadCompleted ||
				chunk.chunk.needsMesh || chunk.chunk.isAnyMeshBlocking)
				chunk.chunk.pendingRemove = true;
			else
			{
				foreach(int proc; 0 .. resources.processorCount)
					resources.getProcessor(proc).removeChunk(chunk.chunk);

				chunksTerrain.remove(chunk.position);
				chunk.chunk.deinitialise();
			}
		}
	}

    private void manageChunkState(ref BasicChunk chunk)
	{
		Chunk c = chunk.chunk;
		if(c.needsData && !c.isAnyMeshBlocking) 
		{
			auto ngo = NoiseGeneratorOrder(c, chunk.position.toVec3d);
			ngo.loadChunk = true;
			ngo.setLoadAll();
			noiseGeneratorManager.generate(ngo);
		}
		if(c.dataLoadCompleted)
		{
			c.needsMesh = true;
			c.dataLoadCompleted = false;
		}

		if(c.needsMesh && !c.needsData && !c.dataLoadBlocking && !c.dataLoadCompleted)
		{
			if(c.airCount == ChunkData.chunkOverrunDimensionsCubed || 
			   c.solidCount == ChunkData.chunkOverrunDimensionsCubed) 
			{
				chunksTerrain.remove(chunk.position);
				chunk.chunk.deinitialise();
				chunkHoles[chunk.position] = ChunkState.hibernated;
				chunksHibernated++;
				return;
			}
			else
			{
				foreach(int proc; 0 .. resources.processorCount)
					resources.getProcessor(proc).meshChunk(c);
			}
			c.needsMesh = false;
		}

		while(!setBlockCommands.empty)
		{
			SetBlockCommand command = setBlockCommands.front;
			setBlockCommands.remove(0);


		}
	}

	private bool isChunkInBounds(ChunkPosition camera, ChunkPosition position)
	{
		return position.x >= camera.x - settings_.removeRange.x && position.x < camera.x + settings_.removeRange.x &&
			position.y >= camera.y - settings_.removeRange.y && position.y < camera.y + settings_.removeRange.y &&
			position.z >= camera.z - settings_.removeRange.z && position.z < camera.z + settings_.removeRange.z;
	}

    enum SetBlockFailureReason
    {
        success = 0,
        outOfBounds,
        chunkNotLoaded,
		chunkIsHibernated
    }

    Event!(SetBlockCommand, SetBlockFailureReason) onSetBlockFailure;

    private void executeSetBlockCommand(SetBlockCommand comm)
    {
        int cx = cast(int)floor(comm.x / cast(float)ChunkData.chunkDimensions);
        int cy = cast(int)floor(comm.y / cast(float)ChunkData.chunkDimensions);
        int cz = cast(int)floor(comm.z / cast(float)ChunkData.chunkDimensions);

        int lx = cast(int)(comm.x - (cx * ChunkData.chunkDimensions));
        int ly = cast(int)(comm.y - (cy * ChunkData.chunkDimensions));
        int lz = cast(int)(comm.z - (cz * ChunkData.chunkDimensions));

        if(lx < 0) lx = lx + (ChunkData.chunkDimensions - 1);
        if(ly < 0) ly = ly + (ChunkData.chunkDimensions - 1);
        if(lz < 0) lz = lz + (ChunkData.chunkDimensions - 1);

        //BasicChunk* chunk = ChunkPosition(cx, cy, cz) in chunksTerrain;
        
		auto chunkPosition = ChunkPosition(cx, cy, cz);
		ChunkState* state = chunkPosition in chunkHoles;

		BasicChunk chunk;

		if(state is null || *state == ChunkState.hibernated || *state == ChunkState.notLoaded)
		{
			if(comm.forceLoad)
			{
				if(*state == ChunkState.hibernated)
				{

				}

				return;
			}
			else
			{
				onSetBlockFailure.emit(comm, state is null ? SetBlockFailureReason.chunkNotLoaded : (*state == ChunkState.hibernated ? SetBlockFailureReason.chunkIsHibernated : SetBlockFailureReason.chunkNotLoaded));
				return;
			}
		}
		else if(*state == ChunkState.active)
		{
			auto tc = chunkPosition in chunksTerrain;
			assert(tc !is null);
			chunk = *tc;
		}

        setBlockOtherChunkOverruns(comm.voxel, lx, ly, lz, chunk);

        chunk.chunk.set(lx, ly, lz, comm.voxel);
        if(!comm.forceLoad) chunk.chunk.needsMesh = true;
    }

    // TODO: Implement PxPz, PxNz, NxPz, NxNz
	private immutable vec3i[][] chunkOffsets = [
		// Nx Ny Nz
		[vec3i(-1, 0, 0), vec3i(0, -1, 0), vec3i(0, 0, -1), vec3i(-1, -1, 0), vec3i(-1, 0, -1), vec3i(0, -1, -1), vec3i(-1, -1, -1)],
		// Nx Ny Pz
		[vec3i(-1, 0, 0), vec3i(0, -1, 0), vec3i(0, 0, 1), vec3i(-1, -1, 0), vec3i(-1, 0, 1), vec3i(0, -1, 1), vec3i(-1, -1, 1)],
		// Nx Ny 
		[vec3i(-1, 0, 0), vec3i(0, -1, 0), vec3i(-1, -1, 0)],
		// Nx Py Nz
		[vec3i(-1, 0, 0), vec3i(0, 1, 0), vec3i(0, 0, -1), vec3i(-1, 1, 0), vec3i(-1, 0, -1), vec3i(0, 1, -1), vec3i(-1, 1, -1)],
		// Nx Py Pz
		[vec3i(-1, 0, 0), vec3i(0, 1, 0), vec3i(0, 0, 1), vec3i(-1, 1, 0), vec3i(-1, 0, 1), vec3i(0, 1, 1), vec3i(-1, 1, 1)],
		// Nx Py
		[vec3i(-1, 0, 0), vec3i(0, 1, 0), vec3i(-1, 1, 0)],
		// Nx Nz
		[vec3i(-1, 0, 0), vec3i(0, 0, -1), vec3i(-1, 0, -1)],
		// Nx Pz
		[vec3i(-1, 0, 0), vec3i(0, 0, 1), vec3i(-1, 0, 1)],
		// Nx
		[vec3i(-1, 0, 0)],
		// Px Ny Nz
		[vec3i(1, 0, 0), vec3i(0, -1, 0), vec3i(0, 0, -1), vec3i(1, -1, 0), vec3i(1, 0, -1), vec3i(0, -1, -1), vec3i(1, -1, -1)],
		// Px Ny Pz
		[vec3i(1, 0, 0), vec3i(0, -1, 0), vec3i(0, 0, 1), vec3i(1, -1, 0), vec3i(1, 0, 1), vec3i(0, -1, 1), vec3i(1, -1, 1)],
		// Px Ny 
		[vec3i(1, 0, 0), vec3i(0, -1, 0), vec3i(1, -1, 0)],
		// Px Py Nz
		[vec3i(1, 0, 0), vec3i(0, 1, 0), vec3i(0, 0, -1), vec3i(1, 1, 0), vec3i(1, 0, -1), vec3i(0, 1, -1), vec3i(1, 1, -1)],
		// Px Py Pz
		[vec3i(1, 0, 0), vec3i(0, 1, 0), vec3i(0, 0, 1), vec3i(1, 1, 0), vec3i(1, 0, 1), vec3i(0, 1, 1), vec3i(1, 1, 1)],
		// Px Py
		[vec3i(1, 0, 0), vec3i(0, 1, 0), vec3i(1, 1, 0)],
		// Nx Nz
		[vec3i(1, 0, 0), vec3i(0, 0, -1), vec3i(1, 0, -1)],
		// Nx Pz
		[vec3i(1, 0, 0), vec3i(0, 0, 1), vec3i(1, 0, 1)],
		// Px
		[vec3i(1, 0, 0)],
		// Ny Nz
		[vec3i(0, -1, 0), vec3i(0, 0, -1), vec3i(0, -1, -1)],
		// Ny Pz
		[vec3i(0, -1, 0), vec3i(0, 0, 1), vec3i(0, -1, 1)],
		// Ny
		[vec3i(0, -1, 0)],
		// Py Nz
		[vec3i(0, 1, 0), vec3i(0, 0, -1), vec3i(0, 1, -1)],
		// Py Pz
		[vec3i(0, 1, 0), vec3i(0, 0, 1), vec3i(0, 1, 1)],
		// Py
		[vec3i(0, 1, 0)],
		// Nz
		[vec3i(0, 0, -1)],
		// Pz
		[vec3i(0, 0, 1)]
	];

	private void setBlockOtherChunkOverruns(Voxel voxel, int x, int y, int z, BasicChunk host) 
	in {
		assert(x >= 0 && x < ChunkData.chunkDimensions);
		assert(y >= 0 && y < ChunkData.chunkDimensions);
		assert(z >= 0 && z < ChunkData.chunkDimensions);
	}
	body {
		if(x == 0) {
			if(y == 0) {
				if(z == 0) {
					foreach(vec3i off; chunkOffsets[0])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == ChunkData.chunkDimensions - 1) {
					foreach(vec3i off; chunkOffsets[1])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(vec3i off; chunkOffsets[2])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
			else if(y == ChunkData.chunkDimensions - 1) {
				if(z == 0) {
					foreach(vec3i off; chunkOffsets[3])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == ChunkData.chunkDimensions - 1) {
					foreach(vec3i off; chunkOffsets[4])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(vec3i off; chunkOffsets[5])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
			else {
				if(z == 0) {
					foreach(vec3i off; chunkOffsets[6])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == ChunkData.chunkDimensions - 1) {
					foreach(vec3i off; chunkOffsets[7]) 
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(vec3i off; chunkOffsets[8])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
		}
		else if(x == ChunkData.chunkDimensions - 1) {
			if(y == 0) {
				if(z == 0) {
					foreach(vec3i off; chunkOffsets[9])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == ChunkData.chunkDimensions - 1) {
					foreach(vec3i off; chunkOffsets[10])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(vec3i off; chunkOffsets[11])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
			else if(y == ChunkData.chunkDimensions - 1) {
				if(z == 0) {
					foreach(vec3i off; chunkOffsets[12])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == ChunkData.chunkDimensions - 1) {
					foreach(vec3i off; chunkOffsets[13])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(vec3i off; chunkOffsets[14])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
			else {
				if(z == 0) {
					foreach(vec3i off; chunkOffsets[15])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == ChunkData.chunkDimensions - 1) {
					foreach(vec3i off; chunkOffsets[16]) 
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(vec3i off; chunkOffsets[17])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
		}

		if(y == 0) {
			if(z == 0) {
				foreach(vec3i off; chunkOffsets[18])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
			else if(z == ChunkData.chunkDimensions - 1) {
				foreach(vec3i off; chunkOffsets[19])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
			else {
				foreach(vec3i off; chunkOffsets[20])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
		}
		else if(y == ChunkData.chunkDimensions - 1) {
			if(z == 0) {
				foreach(vec3i off; chunkOffsets[21])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
			else if(z == ChunkData.chunkDimensions - 1) {
				foreach(vec3i off; chunkOffsets[22])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
			else {
				foreach(vec3i off; chunkOffsets[23])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
		}

		if(z == 0) {
			foreach(vec3i off; chunkOffsets[24])
				setBlockForChunkOffset(off, host, x, y, z, voxel);
			return;
		}
		else if(z == ChunkData.chunkDimensions - 1) {
			foreach(vec3i off; chunkOffsets[25])
				setBlockForChunkOffset(off, host, x, y, z, voxel);
			return;
		}
	}

	private void setBlockForChunkOffset(vec3i off, BasicChunk host, int x, int y, int z, Voxel voxel) {
		ChunkPosition cp = ChunkPosition(host.position.x + off.x, host.position.y + off.y, host.position.z + off.z);
		BasicChunk* c = cp in chunksTerrain;

		assert(c !is null);

		int newX = x + (-off.x * ChunkData.chunkDimensions);
		int newY = y + (-off.y * ChunkData.chunkDimensions);
		int newZ = z + (-off.z * ChunkData.chunkDimensions);

		c.chunk.set(newX, newY, newZ, voxel);
		//c.countAir();
		c.chunk.needsMesh = true;
	}
}