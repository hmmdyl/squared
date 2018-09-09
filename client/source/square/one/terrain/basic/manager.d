module square.one.terrain.basic.manager;

import moxana.graphics.rendercontext;
import moxana.graphics.rh;

import square.one.terrain.basic.chunk;
import square.one.terrain.noisegen;
import square.one.terrain.resources;

import square.one.utils.math : flattenIndex;
import square.one.utils.floor : ifloordiv;

import containers.hashset;
import std.experimental.allocator.mallocator;
import std.datetime.stopwatch;

import moxana.utils.event;

import gfm.math;

import std.math;
import std.conv : to;
import std.file;

alias createNgFunc = NoiseGenerator delegate();

struct BasicTmSettings 
{
    int addRange;
    int removeRange;
    createNgFunc createNg;
    Resources resources;

	const string worldDir;
}

struct AddChunkCommand
{

}

struct RemoveChunkCommand 
{

}

/// set a block on the terrain
struct SetBlockCommand 
{
    /// block position
    long x;
    /// ditto
    long y;
    /// ditto
    long z;
    /// the new voxel
    Voxel voxel;

    // force the engine to load the chunk if not already
    bool forceLoad;

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

	private bool regionExists(vec3i r, out string fin)
	{
		import std.path : buildPath;

		string regionName;
		scope(exit) delete regionName;
		regionName ~= to!string(r.x);
		regionName ~= '_';
		regionName ~= to!string(r.y);
		regionName ~= '_';
		regionName ~= to!string(r.z);		
		regionName ~= ".sqr";
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
					buffer = neighbours[i] in buffers;

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
	}
}

final class BasicTerrainManager 
{
    private BasicChunk[ChunkPosition] chunksTerrain;

    const BasicTmSettings settings;

    vec3f cameraPosition;

    this(BasicTmSettings s)
    {
        this.settings = s;
    }

    void update()
    {

    }

    private void manageChunkState(Chunk chunk, BasicChunk* bc)
	in {
		assert(chunk is bc.chunk);
	}
    body {
		if(chunk.needsData)
		{
			
		}
    }

    enum SetBlockFailureReason
    {
        success = 0,
        outOfBounds,
        chunkNotLoaded,
    }

    Event!(SetBlockCommand, SetBlockFailureReason) onSetBlockFailure;

    private void executeSetBlockCommand(SetBlockCommand comm, BasicChunk* chunk)
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
        
        if(chunk is null)
        {
            if(comm.forceLoad)
            {
                // todo
                return;
            }
            else
            {
                onSetBlockFailure.emit(comm, SetBlockFailureReason.chunkNotLoaded);
                return;
            }
        }

        setBlockOtherChunkOverruns(comm.voxel, lx, ly, lz, *chunk);

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

final class BasicTerrainRenderer : IRenderHandler
{
    BasicTerrainManager basicTerrainManager;

    this(BasicTerrainManager basicTerrainManager)
    {
        this.basicTerrainManager = basicTerrainManager;
    }

    void renderPostPhysical(RenderContext rc, ref LocalRenderContext lrc) {}
    void ui(RenderContext rc) {}

    void shadowDepthMapPass(RenderContext rc, ref LocalRenderContext lrc)
    {

    }

    void renderPhysical(RenderContext rc, ref LocalRenderContext lrc)
    {

    }
}

BasicTmSettings createTmSettingsDefault(Resources r)
{
    BasicTmSettings s;
    s.addRange = 4;
    s.removeRange = 6;
    s.createNg = () { return new DefaultNoiseGenerator; };
    s.resources = r;
    return s;
}
