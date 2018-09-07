module square.one.terrain.chunk;

import square.one.terrain.voxel;
import square.one.terrain.manager;
import square.one.terrain.rlecompressor;
import square.one.terrain.resources;
import square.one.utils.disposable;

import moxana.entity.transform;

import gfm.math;
import std.math;

import std.datetime.stopwatch;

import core.atomic;
import core.memory;
import std.experimental.allocator.mallocator;

enum int chunkDimensions = 16;
enum int chunkOverrunDimensions = 18;
enum int voxelOffset = 1;

enum int chunkDimensionsCubed = chunkDimensions ^^ 3;
enum int chunkOverrunDimensionsCubed = chunkOverrunDimensions ^^ 3;

enum int voxelsPerMetre = 4;
enum float voxelScale = 0.25f;

enum float chunkDimensionsMetres = chunkDimensions * voxelScale;
enum float invChunkDimensionsMetres = 1f / chunkDimensionsMetres;

interface IVoxelBuffer 
{
	@property int dimensionsProper();
	@property int dimensionsTotal();
	@property int overrun();
	@property float voxelScale();

	@property bool hasData();
	@property void hasData(bool);

	@property int lod();
	@property void lod(int);
	@property int blockskip();
	@property void blockskip(int);

	@property int airCount();
	@property void airCount(int);

	Voxel get(int x, int y, int z);
	Voxel getRaw(int x, int y, int z);
	void set(int x, int y, int z, Voxel voxel);
	void setRaw(int x, int y, int z, Voxel voxel);
}

interface ILoadableVoxelBuffer : IVoxelBuffer 
{
	@property bool needsData();
	@property void needsData(bool);
	@property bool dataLoadBlocking();
	@property void dataLoadBlocking(bool);
	@property bool dataLoadCompleted();
	@property void dataLoadCompleted(bool);
}

interface IRenderableVoxelBuffer : IVoxelBuffer 
{
	@property ref Transform transform();
	@property void transform(ref Transform);

	@property ref void*[] renderData();
}

interface IMeshableVoxelBuffer : IVoxelBuffer 
{
	@property int meshingOverrun(); 

	@property bool needsMesh();
	@property void needsMesh(bool);
	@property bool meshBlocking(size_t processorID);
	@property void meshBlocking(bool v, size_t processorID);
	@property bool isAnyMeshBlocking();
}

interface ICompressableVoxelBuffer : IVoxelBuffer 
{
	@property bool isCompressed();
	@property void isCompressed(bool);

	@property ref Voxel[] voxels();
	@property void voxels(Voxel[]);
	void deallocateVoxelData();

	@property ref void* compressedData();
	@property void compressedData(void*, size_t);
	void deallocateCompressedData();
}

class Chunk : IVoxelBuffer, ILoadableVoxelBuffer, IRenderableVoxelBuffer, IMeshableVoxelBuffer, ICompressableVoxelBuffer
{
	private Voxel[] voxelData;
    private ubyte[] _compressedData;

    //ChunkPosition position;

    this(Resources resources) {
        _meshBlocking.length = resources.processorCount;
        _renderData.length = resources.processorCount;
    }

    void initialise() {
		needsData = false;
        dataLoadBlocking = false;
        dataLoadCompleted = false;
        needsMesh = false;

        if(voxelData !is null)
            deallocateVoxelData();
        if(_compressedData !is null)
            deallocateCompressedData();

        voxels = cast(Voxel[])Mallocator.instance.allocate(dimensionsTotal ^^ 3 * Voxel.sizeof);
        voxels[] = Voxel(0, 0, 0, 0);

        foreach(ref rd; renderData)
            rd = null;
    }

    void deinitialise() {
        if(voxelData !is null)
            deallocateVoxelData();
        if(_compressedData !is null)
            deallocateCompressedData();
    }

    Voxel get(int x, int y, int z) 
    in { assert(voxelData !is null); }
    body {
        x += blockskip * overrun;
        y += blockskip * overrun;
        z += blockskip * overrun;
        x = x >> _lod;
        y = y >> _lod;
        z = z >> _lod;
        return voxelData[flattenIndex(x, y, z)];
    }

    Voxel getRaw(int x, int y, int z) 
    in { assert(voxelData !is null); }
    body {
        x += overrun;
        y += overrun;
        z += overrun;
        return voxelData[flattenIndex(x, y, z)];
    }
    
    void set(int x, int y, int z, Voxel voxel) 
    in { assert(voxelData !is null); }
    body {
        x += blockskip * overrun;
        y += blockskip * overrun;
        z += blockskip * overrun;
        x = x >> _lod;
        y = y >> _lod;
        z = z >> _lod;
        voxelData[flattenIndex(x, y, z)] = voxel;
    }

    void setRaw(int x, int y, int z, Voxel voxel) 
    in { assert(voxelData !is null); }
    body {
        x += overrun;
        y += overrun;
        z += overrun;
        voxelData[flattenIndex(x, y, z)] = voxel;
    }

    pragma(inline, true)
    @property int dimensionsProper() { return chunkDimensions; }
    pragma(inline, true)
    @property int dimensionsTotal() { return chunkDimensions + voxelOffset * 2; }
    pragma(inline, true)
    @property int overrun() { return voxelOffset; }

    private shared(bool) _hasData;
    @property bool hasData() { return atomicLoad(_hasData); }
    @property void hasData(bool n) { atomicStore(_hasData, n); }

    /*private shared(int) _lod;
    @property int lod() { return atomicLoad(_lod); }
    @property void lod(int n) { atomicStore(_lod, n); }

    private shared(int) _blockskip;
    @property int blockskip() { return atomicLoad(_blockskip); }
    @property void blockskip(int n) { atomicStore(_blockskip, n); }*/

    private int _lod, _blockskip;
    @property int lod() { return _lod; }
    @property void lod(int n) { _lod = n; }

    @property int blockskip() { return _blockskip; }
    @property void blockskip(int n) { _blockskip = n; }

    private int _airCount;
    @property int airCount() { return _airCount; }
    @property void airCount(int ac) { _airCount = ac; }

    private shared(bool) _needsData;
    @property bool needsData() { return atomicLoad(_needsData); }
    @property void needsData(bool n) { atomicStore(_needsData, n); }

    private shared(bool) _dataLoadBlocking;
    @property bool dataLoadBlocking() { return atomicLoad(_dataLoadBlocking); }
    @property void dataLoadBlocking(bool n) { atomicStore(_dataLoadBlocking, n); }

    private shared(bool) _dataLoadCompleted;
    @property bool dataLoadCompleted() { return atomicLoad(_dataLoadCompleted); }
    @property void dataLoadCompleted(bool n) { atomicStore(_dataLoadCompleted, n); }

	private Transform _transform;
	@property Transform transform() { return _transform; }
	@property void transform(Transform n) { _transform = n; }

    private void*[] _renderData;
    @property ref void*[] renderData() { return _renderData; }

    private shared(bool) _needsMesh;
    @property bool needsMesh() { return atomicLoad(_needsMesh); }
    @property void needsMesh(bool n) { atomicStore(_needsMesh, n); }

    private shared bool[] _meshBlocking;
    @property bool meshBlocking(size_t id) { return atomicLoad(_meshBlocking[id]); }
    @property void meshBlocking(bool n, size_t id) { atomicStore(_meshBlocking[id], n); }

    @property bool isAnyMeshBlocking() {
        foreach(i; 0 .. _meshBlocking.length)
            if(meshBlocking(i))
                return true;
        return false;
    }

    private shared bool _isCompressed;
    @property bool isCompressed() { return atomicLoad(_isCompressed); }
    @property void isCompressed(bool n) { atomicStore(_isCompressed, n); }

    @property ref Voxel[] voxels() { return voxelData; }
    @property void voxels(Voxel[] v) { voxelData = v; }

    void deallocateVoxelData() { 
        assert(voxelData !is null);
        Mallocator.instance.deallocate(voxelData); 
        voxelData = null;
    }

    @property void* compressedData() { return cast(void*)_compressedData; }
    @property void compressedData(void* v, size_t n) { _compressedData = cast(ubyte[])v[0 .. n]; }

    void deallocateCompressedData() {
        assert(_compressedData !is null);
        Mallocator.instance.deallocate(_compressedData);
        _compressedData = null;
    }

    pragma(inline, true)
    static int flattenIndex(int x, int y, int z) {
        return x + voxelOffset * (y + voxelOffset * z);
    }

    private shared bool _pendingRemove;
    @property bool pendingRemove() { return atomicLoad(_pendingRemove); }
    @property void pendingRemove(bool n) { atomicStore(_pendingRemove, n); }
}

enum ChunkNeighbours
{
    nxNyNz, nyNz, pxNyNz,
	nxNy, ny, pxNy,
	nxNyPz, nyPz, pxNyPz,

	nxNz, nz, pxNz,
	nx, /*curr*/ px,
	nxPz, pz, pxPz,

	nxPyNz, pyNz, pxPyNz,
	nxPy, py, pxPy,
	nxPyPz, pyPz, pxPyPz
}

vec3i chunkNeighbourToOffset(ChunkNeighbours n)
{
	final switch(n) with(ChunkNeighbours)
	{
		case nxNyNz: return vec3i(-1, -1, -1);
		case nyNz: return vec3i(0, -1, -1);
		case pxNyNz: return vec3i(1, -1, -1);
		case nxNy: return vec3i(-1, -1, 0);
		case ny: return vec3i(0, -1, 0);
		case pxNy: return vec3i(1, -1, 0);
		case nxNyPz: return vec3i(-1, -1, 1);
		case nyPz: return vec3i(0, -1, 1);
		case pxNyPz: return vec3i(1, -1, 1);

		case nxNz: return vec3i(-1, 0, -1);
		case nz: return vec3i(0, 0, -1);
		case pxNz: return vec3i(1, 0, -1);
		case nx: return vec3i(-1, 0, 0);
		case px: return vec3i(1, 0, 0);
		case nxPz: return vec3i(-1, 0, 1);
		case pz: return vec3i(0, 0, 1);
		case pxPz: return vec3i(1, 0, 1);

		case nxPyNz: return vec3i(-1, 1, -1);
		case pyNz: return vec3i(0, 1, -1);
		case pxPyNz: return vec3i(1, 1, -1);
		case nxPy: return vec3i(-1, 1, 0);
		case py: return vec3i(0, 1, 0);
		case pxPy: return vec3i(1, 1, 0);
		case nxPyPz: return vec3i(-1, 1, 1);
		case pyPz: return vec3i(0, 1, 1);
		case pxPyPz: return vec3i(1, 1, 1);
	}	
}

/*final class Chunk {
	public ChunkPosition position;
	private ubyte[] voxelsCompressed;
	private Voxel[] voxels;

	private enum memSize = chunkOverrunDimensionsCubed * Voxel.sizeof;

	public TerrainManager manager;

	public void*[] renderData;

	private shared(bool) _needsNoise, _noiseBlocking, _noiseCompleted;
	private shared(bool) _needsMesh;
	private shared(bool[]) _meshBlocking;
	private shared(bool) _pendingRemove;
	private shared(bool) _isArrCompressed;
	private shared(bool) _isInitialised = false;

	@property bool needsNoise() { return atomicLoad(_needsNoise); }
	@property void needsNoise(bool v) { atomicStore(_needsNoise, v); }
	@property bool noiseBlocking() { return atomicLoad(_noiseBlocking); }
	@property void noiseBlocking(bool v) { atomicStore(_noiseBlocking, v); }
	@property bool noiseCompleted() { return atomicLoad(_noiseCompleted); }
	@property void noiseCompleted(bool v) { atomicStore(_noiseCompleted, v); }

	@property bool needsMesh() { return atomicLoad(_needsMesh); }
	@property void needsMesh(bool v) { return atomicStore(_needsMesh, v); }

	@property bool meshBlocking(size_t id) { return atomicLoad(_meshBlocking[id]); }
	@property void meshBlocking(bool v, size_t id) { atomicStore(_meshBlocking[id], v); }

	@property bool pendingRemove() { return atomicLoad(_pendingRemove); }
	@property void pendingRemove(bool v) { return atomicStore(_pendingRemove, v); }

	@property bool isArrayCompressed() { return atomicLoad(_isArrCompressed); }
	@property void isArrayCompressed(bool v) { atomicStore(_isArrCompressed, v); }

	@property bool isInitialised() { return atomicLoad(_isInitialised); }
	@property void isInitialised(bool v) { atomicStore(_isInitialised, v); }

	int airCount;

	int lod;
	int blockskip;

	package StopWatch lastRefSw = StopWatch(AutoStart.no);

	public this(TerrainManager man) {
		manager = man;
		_meshBlocking.length = manager.resources.processorCount;
		renderData.length = manager.resources.processorCount;
		foreach(int i; 0 .. manager.resources.processorCount) {
			_meshBlocking[i] = false;
			renderData[i] = null;
		}
		voxels = null;
		voxelsCompressed = null;
		isInitialised = false;
	}

	/*private bool isDisposed = false;
	void dispose() {
		if(voxels !is null)
			Mallocator.instance.deallocate(voxels);
		if(voxelsCompressed !is null)
			Mallocator.instance.deallocate(voxelsCompressed);

		isDisposed = true;
	}

	~this() {
		if(!isDisposed)
			dispose();
	}/

	public @property bool isMeshBlocking() {
		foreach(size_t i; 0 .. _meshBlocking.length)
			if(meshBlocking(i))
				return true;
		return false;
	}

	public void initialise(ChunkPosition pos) {
		this.position = pos;

		needsNoise = false;
		noiseBlocking = false;
		noiseCompleted = false;
		needsMesh = false;
		pendingRemove = false;

		if(voxelsCompressed !is null)
			Mallocator.instance.deallocate(voxelsCompressed);
		voxelsCompressed = null;

		if(voxels is null) 
			voxels = cast(Voxel[])Mallocator.instance.allocate(memSize);
		voxels[] = Voxel(0, 0, 0, 0);

		isArrayCompressed = false;

		isInitialised = true;
	}

	void deinitialise() {
		if(voxels !is null)
			Mallocator.instance.deallocate(voxels);
		if(voxelsCompressed !is null)
			Mallocator.instance.deallocate(voxelsCompressed);

		voxels = null;
		voxelsCompressed = null;

		isArrayCompressed = false;

		isInitialised = false;
	}

	public Voxel get(int x, int y, int z) {
		if(x < -voxelOffset || y < -voxelOffset || z < -voxelOffset || x >= chunkDimensions + voxelOffset || y >= chunkDimensions + voxelOffset || z >= chunkDimensions + voxelOffset)
			return Voxel(0, 0, 0, 0);

		if(!isArrayCompressed) {
			return voxels[flattenIndex(x + voxelOffset, y + voxelOffset, z + voxelOffset)];
		}
		else {
			throw new Exception("Error! Voxel array is compressed.");
		}
	}

	public void set(int x, int y, int z, Voxel voxel) {
		if(x < -voxelOffset || y < -voxelOffset || z < -voxelOffset || x >= chunkDimensions + voxelOffset || y >= chunkDimensions + voxelOffset || z >= chunkDimensions + voxelOffset)
			return;

		if(!isArrayCompressed) {
			voxels[flattenIndex(x + voxelOffset, y + voxelOffset, z + voxelOffset)] = voxel;
		}
		else {
			throw new Exception("Error! Voxel array is compressed.");
		}
	}

	void countAir() {
		if(voxelsCompressed) return;

		airCount = 0;

		foreach(int i; 0 .. chunkOverrunDimensionsCubed) {
			if(voxels[i].material == 0)
				airCount++;
		}
	}

	package void compress() {
		isArrayCompressed = true;
		atomicFence();

		voxelsCompressed = rleCompressDualPass(voxels);
		Mallocator.instance.deallocate(voxels);
		voxels = null;
	}

	package void decompress() {
		isArrayCompressed = false;
		atomicFence();

		voxels = rleDecompressCheat(voxelsCompressed, chunkOverrunDimensionsCubed);
		Mallocator.instance.deallocate(voxelsCompressed);
		voxelsCompressed = null;
	}

	pragma(inline, true)
	static int flattenIndex(int x, int y, int z) {
		return x + chunkOverrunDimensions * (y + chunkOverrunDimensions * z);
	}
}

final class ChunkBuffer {
	public ChunkPosition position;
	private ubyte[] voxelsCompressed;
	private Voxel[] voxels;

	private shared(bool) _isArrCompressed;
	private shared(bool) _isInitialised = false;

	@property bool isArrayCompressed() { return atomicLoad(_isArrCompressed); }
	@property void isArrayCompressed(bool v) { atomicStore(_isArrCompressed, v); }
	
	@property bool isInitialised() { return atomicLoad(_isInitialised); }
	@property void isInitialised(bool v) { atomicStore(_isInitialised, v); }

	void initialise(ChunkPosition cp) {

	}
}*/

struct ChunkPosition 
{
	int x, y, z;

	this(int x, int y, int z) 
	{
		this.x = x;
		this.y = y;
		this.z = z;
	}

	size_t toHash() const @safe pure nothrow 
	{
		size_t hash = 17;
		hash = hash * 31 + x;
		hash = hash * 31 + y;
		hash = hash * 31 + z;
		return hash;
	}

	bool opEquals(ref const ChunkPosition other) const @safe pure nothrow 
	{
		return other.x == x && other.y == y && other.z == z;
	}

	vec3f toVec3f() 
	{
		return vec3f(x * chunkDimensionsMetres, y * chunkDimensionsMetres, z * chunkDimensionsMetres);
	}

	vec3d toVec3d() 
	{
		return vec3d(x * chunkDimensionsMetres, y * chunkDimensionsMetres, z * chunkDimensionsMetres);
	}

	vec3i toVec3i() { return vec3i(x, y, z); }

	static ChunkPosition fromVec3f(vec3f v) 
	{
		return ChunkPosition(
			cast(int)(v.x * invChunkDimensionsMetres), 
			cast(int)(v.y * invChunkDimensionsMetres), 
			cast(int)(v.z * invChunkDimensionsMetres));
	}

	static ChunkPosition fromVec3d(vec3d v)
	{
		return ChunkPosition(
			cast(int)(v.x * invChunkDimensionsMetres), 
			cast(int)(v.y * invChunkDimensionsMetres), 
			cast(int)(v.z * invChunkDimensionsMetres));
	}

	static vec3f blockPosRealCoord(ChunkPosition cp, vec3i block) {
		vec3f cpReal = cp.toVec3f();
		cpReal.x += (block.x * voxelScale);
		cpReal.y += (block.y * voxelScale);
		cpReal.z += (block.z * voxelScale);
		return cpReal;
	}

	static vec3l realCoordToBlockPos(vec3f pos) {
		vec3l bp;
		bp.x = cast(long)floor(pos.x * voxelsPerMetre);
		bp.y = cast(long)floor(pos.y * voxelsPerMetre);
		bp.z = cast(long)floor(pos.z * voxelsPerMetre);
		return bp;
	}
}