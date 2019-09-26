module squareone.voxel.chunk;

import moxane.core.transformation;
import squareone.voxel.resources;
import squareone.voxel.voxel;

import dlib.math.vector;
import std.math : floor;

import core.atomic;
import std.experimental.allocator.mallocator : Mallocator;

alias BlockOffset = Vector!(int, 3);
alias BlockPosition = Vector!(long, 3);

struct ChunkData
{
	enum int chunkDimensions = 32;
	enum int chunkOverrunDimensions = chunkDimensions + 2;
	enum int voxelOffset = 1;

	enum int chunkDimensionsCubed = chunkDimensions ^^ 3;
	enum int chunkOverrunDimensionsCubed = chunkOverrunDimensions ^^ 3;

	enum int voxelsPerMetre = 4;
	enum float voxelScale = 0.25f;

	enum float chunkDimensionsMetres = chunkDimensions * voxelScale;
	enum float invChunkDimensionsMetres = 1f / chunkDimensionsMetres;
}

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

	@property int solidCount();
	@property void solidCount(int);
	@property int airCount();
	@property void airCount(int);
	@property int fluidCount();
	@property void fluidCount(int);

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

interface IReadonlyVoxelBuffer : IVoxelBuffer
{
	@property int readonlyRefs();
	void incrementReadonlyRef();
	void decrementReadonlyRef();
}

interface IRenderableVoxelBuffer : IVoxelBuffer 
{
	@property ref Transform transform();
	@property void transform(ref Transform);

	@property ref void*[] renderData();
}

interface IMeshableVoxelBuffer : IVoxelBuffer, IRenderableVoxelBuffer 
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

	@property ref ubyte[] compressedData();
	@property void compressedData(ubyte[]);
	void deallocateCompressedData();
}

class Chunk : IVoxelBuffer, ILoadableVoxelBuffer, IRenderableVoxelBuffer, IMeshableVoxelBuffer, ICompressableVoxelBuffer, IReadonlyVoxelBuffer
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
		hasData = false;

		lod = -1;
		blockskip = 0;

		solidCount = 0;
		airCount = 0;
		fluidCount = 0;

		foreach(ref void* rd; _renderData)
			rd = null;

		_readonlyRefCount = 0;

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

		blockskip = 0;
		lod = -1;
		solidCount = 0;
		fluidCount = 0;
		airCount = 0;
    }

    Voxel get(int x, int y, int z) 
    in { assert(voxelData !is null); }
	in { assert(voxelData.length == dimensionsTotal ^^ 3); }
    do {
		debug assert(voxelData !is null);
		debug assert(voxelData.length == dimensionsTotal ^^ 3);

        x += blockskip * overrun;
        y += blockskip * overrun;
        z += blockskip * overrun;
        x = x >> _lod;
        y = y >> _lod;
        z = z >> _lod;
		try
			return voxelData[flattenIndex(x, y, z)];
		catch(Error e)
		{
			import std.stdio : writeln;
			writeln("x: ", x, " y: ", y, " z: ", z, " lod: ", _lod, " index: ", flattenIndex(x, y, z));
			throw e;
			//return Voxel();
		}
    }

    Voxel getRaw(int x, int y, int z) 
    in { assert(voxelData !is null); }
	in { assert(voxelData.length == dimensionsTotal ^^ 3); }
    do {
        x += overrun;
        y += overrun;
        z += overrun;
        return voxelData[flattenIndex(x, y, z)];
    }

    void set(int x, int y, int z, Voxel voxel) 
    in { assert(voxelData !is null); }
	in { assert(voxelData.length == dimensionsTotal ^^ 3); }
    do {
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
	in { assert(voxelData.length == dimensionsTotal ^^ 3); }
    do {
        x += overrun;
        y += overrun;
        z += overrun;
        voxelData[flattenIndex(x, y, z)] = voxel;
    }

    //pragma(inline, true)
    @property int dimensionsProper() { return ChunkData.chunkDimensions; }
    //pragma(inline, true)
    @property int dimensionsTotal() { return ChunkData.chunkDimensions + ChunkData.voxelOffset * 2; }
    //pragma(inline, true)
    @property int overrun() { return ChunkData.voxelOffset; }
	//pragma(inline, true)
		@property float voxelScale() { return ChunkData.voxelScale; }

    private shared(bool) _hasData;
    @property bool hasData() { return atomicLoad(_hasData); }
    @property void hasData(bool n) { atomicStore(_hasData, n); }

    private int _lod, _blockskip;
    @property int lod() { return _lod; }
    @property void lod(int n) { _lod = n; }

    @property int blockskip() { return _blockskip; }
    @property void blockskip(int n) { _blockskip = n; }

    private int _airCount;
    @property int airCount() { return _airCount; }
    @property void airCount(int ac) { _airCount = ac; }

	private int _solidCount;
	@property int solidCount() { return _solidCount; }
	@property void solidCount(int ac) { _solidCount = ac; }
	
	private int fluidCount_;
	@property int fluidCount() { return fluidCount_; }
	@property void fluidCount(int ac) { fluidCount_ = ac; }

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
	@property ref Transform transform() { return _transform; }
	@property void transform(ref Transform n) { _transform = n; }

    private void*[] _renderData;
    @property ref void*[] renderData() { return _renderData; }

	@property int meshingOverrun() { return 0; }

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

    @property ref ubyte[] compressedData() { return _compressedData; }
    @property void compressedData(ubyte[] v) { _compressedData = v; }

    void deallocateCompressedData() {
        assert(_compressedData !is null);
        Mallocator.instance.deallocate(_compressedData);
        _compressedData = null;
    }

    pragma(inline, true)
		static int flattenIndex(int x, int y, int z) {
			return x + ChunkData.chunkOverrunDimensions * (y + ChunkData.chunkOverrunDimensions * z);
		}

    private shared bool _pendingRemove;
    @property bool pendingRemove() { return atomicLoad(_pendingRemove); }
    @property void pendingRemove(bool n) { atomicStore(_pendingRemove, n); }

	private shared int _readonlyRefCount;
	@property int readonlyRefs() { return atomicLoad(_readonlyRefCount); }
	void incrementReadonlyRef() { atomicOp!"+="(_readonlyRefCount, 1); }
	void decrementReadonlyRef() { atomicOp!"-="(_readonlyRefCount, 1); }
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
	nxPyPz, pyPz, pxPyPz,
	last
}

// in block space of neighbour chunk
private Vector3i[2] boundsNeighbour(ChunkNeighbours n)
{
	ChunkPosition offset = chunkNeighbourToOffset(n);
	Vector3i base, end;
	foreach(x; 0..3)
	{
		base[x] = offset[x] == 1 ? 0 : offset[x] == -1 ? ChunkData.chunkDimensions - 1 : 0;
		end[x] = offset[x] == 1 ? 0 : offset[x] == -1 ? ChunkData.chunkDimensions - 1 : ChunkData.chunkDimensions;
	}
	return [base, end];
}

private Vector3i[2] boundsNeighbourInChunk(ChunkNeighbours n)
{
	ChunkPosition offset = chunkNeighbourToOffset(n);
	Vector3i base, end;
	foreach(x; 0..3)
	{
		base[x] = offset[x] == 1 ? ChunkData.chunkDimensions : offset[x] == -1 ? -1 : 0;
		end[x] = offset[x] == 1 ? ChunkData.chunkDimensions : offset[x] == -1 ? -1 : ChunkData.chunkDimensions;
	}
	return [base, end];
}

private Vector3i[2][26] getNeighbourBounds(Vector3i[2] function(ChunkNeighbours) fn)
{
	Vector3i[2][26] ret;
	foreach(x; 0 .. cast(int)ChunkNeighbours.last)
		ret[x] = fn(cast(ChunkNeighbours)x);
	//pragma(msg, ret);
	return ret;
}

static enum Vector3i[2][26] neighbourBounds = getNeighbourBounds(&boundsNeighbour);
static enum Vector3i[2][26] neighbourBoundsInChunk = getNeighbourBounds(&boundsNeighbourInChunk);

ChunkPosition chunkNeighbourToOffset(ChunkNeighbours n)
{
	final switch(n) with(ChunkNeighbours)
	{
		case nxNyNz: return ChunkPosition(-1, -1, -1);
		case nyNz: return ChunkPosition(0, -1, -1);
		case pxNyNz: return ChunkPosition(1, -1, -1);
		case nxNy: return ChunkPosition(-1, -1, 0);
		case ny: return ChunkPosition(0, -1, 0);
		case pxNy: return ChunkPosition(1, -1, 0);
		case nxNyPz: return ChunkPosition(-1, -1, 1);
		case nyPz: return ChunkPosition(0, -1, 1);
		case pxNyPz: return ChunkPosition(1, -1, 1);

		case nxNz: return ChunkPosition(-1, 0, -1);
		case nz: return ChunkPosition(0, 0, -1);
		case pxNz: return ChunkPosition(1, 0, -1);
		case nx: return ChunkPosition(-1, 0, 0);
		case px: return ChunkPosition(1, 0, 0);
		case nxPz: return ChunkPosition(-1, 0, 1);
		case pz: return ChunkPosition(0, 0, 1);
		case pxPz: return ChunkPosition(1, 0, 1);

		case nxPyNz: return ChunkPosition(-1, 1, -1);
		case pyNz: return ChunkPosition(0, 1, -1);
		case pxPyNz: return ChunkPosition(1, 1, -1);
		case nxPy: return ChunkPosition(-1, 1, 0);
		case py: return ChunkPosition(0, 1, 0);
		case pxPy: return ChunkPosition(1, 1, 0);
		case nxPyPz: return ChunkPosition(-1, 1, 1);
		case pyPz: return ChunkPosition(0, 1, 1);
		case pxPyPz: return ChunkPosition(1, 1, 1);

		case last: throw new Exception("Invalid");
	}	
}

struct ChunkPosition 
{
	int x, y, z;

	this(int x, int y, int z) 
	{
		this.x = x;
		this.y = y;
		this.z = z;
	}

	this(Vector3i v)
	{
		this.x = v.x;
		this.y = v.y;
		this.z = v.z;
	}

	size_t toHash() const @safe pure nothrow 
	{
		size_t hash = 17;
		hash = hash * 31 + x;
		hash = hash * 31 + y;
		hash = hash * 31 + z;
		return hash;
	}

	ChunkPosition opBinary(string op)(ref const ChunkPosition right)
	{
		return mixin("ChunkPosition(this.x"~op~"right.x, this.y"~op~"right.y, this.z"~op~"right.z)");
	}

	int opIndex(size_t offset)
	{
		switch(offset)
		{
			case 0: return x;
			case 1: return y;
			case 2: return z;
			default: throw new Exception("Out of bounds");
		}
	}

	bool opEquals(ref const ChunkPosition other) const @safe pure nothrow 
	{
		return other.x == x && other.y == y && other.z == z;
	}

	Vector3f toVec3f() const
	{
		return Vector3f(x * ChunkData.chunkDimensionsMetres, y * ChunkData.chunkDimensionsMetres, z * ChunkData.chunkDimensionsMetres);
	}

	Vector3d toVec3d() const
	{
		return Vector3d(x * ChunkData.chunkDimensionsMetres, y * ChunkData.chunkDimensionsMetres, z * ChunkData.chunkDimensionsMetres);
	}

	Vector3d toVec3dOffset(BlockOffset offset) const
	{
		BlockPosition p = toBlockPosition(offset);
		Vector3d r;
		r.x = p.x * ChunkData.voxelScale;
		r.y = p.y * ChunkData.voxelScale;
		r.z = p.z * ChunkData.voxelScale;
		return r;
	}

	Vector3i toVec3i() { return Vector3i(x, y, z); }

	BlockPosition toBlockPosition(BlockOffset offset) const
	{
		return BlockPosition(cast(long)x * cast(long)ChunkData.chunkDimensions + cast(long)offset.x, cast(long)y * cast(long)ChunkData.chunkDimensions + cast(long)offset.y, cast(long)z * cast(long)ChunkData.chunkDimensions + cast(long)offset.z);
	}

	BlockOffset toOffset(BlockPosition pos)
	{
		BlockOffset offset;
		offset.x = cast(int)(pos.x - x * ChunkData.chunkDimensions);
		offset.y = cast(int)(pos.y - y * ChunkData.chunkDimensions);
		offset.z = cast(int)(pos.z - z * ChunkData.chunkDimensions);
		return offset;
	}

	static ChunkPosition fromVec3f(Vector3f v) 
	{
		return ChunkPosition(
							 cast(int)(v.x * ChunkData.invChunkDimensionsMetres), 
							 cast(int)(v.y * ChunkData.invChunkDimensionsMetres), 
							 cast(int)(v.z * ChunkData.invChunkDimensionsMetres));
	}

	static ChunkPosition fromVec3d(Vector3d v)
	{
		return ChunkPosition(
							 cast(int)(v.x * ChunkData.invChunkDimensionsMetres), 
							 cast(int)(v.y * ChunkData.invChunkDimensionsMetres), 
							 cast(int)(v.z * ChunkData.invChunkDimensionsMetres));
	}

	static Vector3f blockOffsetRealCoord(ChunkPosition cp, Vector3i block) {
		Vector3f cpReal = cp.toVec3f();
		cpReal.x += (block.x * ChunkData.voxelScale);
		cpReal.y += (block.y * ChunkData.voxelScale);
		cpReal.z += (block.z * ChunkData.voxelScale);
		return cpReal;
	}

	static Vector3d blockPosRealCoord(BlockPosition bp)
	{
		return Vector3d(bp.x * ChunkData.voxelScale, bp.y * ChunkData.voxelScale, bp.z * ChunkData.voxelScale);
	}

	static void blockPosToChunkPositionAndOffset(Vector!(long, 3) block, out ChunkPosition chunk, out Vector3i offset)
	{
		import std.math : floor;
		chunk.x = cast(int)floor(block.x / cast(real)ChunkData.chunkDimensions);
		chunk.y = cast(int)floor(block.y / cast(real)ChunkData.chunkDimensions);
		chunk.z = cast(int)floor(block.z / cast(real)ChunkData.chunkDimensions);
		long snapX = chunk.x * ChunkData.chunkDimensions;
		long snapY = chunk.y * ChunkData.chunkDimensions;
		long snapZ = chunk.z * ChunkData.chunkDimensions;
		offset.x = cast(int)(block.x - snapX);
		offset.y = cast(int)(block.y - snapY);
		offset.z = cast(int)(block.z - snapZ);
	}

	static Vector!(long, 3) realCoordToBlockPos(Vector3f pos) {
		Vector!(long, 3) bp;
		bp.x = cast(long)floor(pos.x * ChunkData.voxelsPerMetre);
		bp.y = cast(long)floor(pos.y * ChunkData.voxelsPerMetre);
		bp.z = cast(long)floor(pos.z * ChunkData.voxelsPerMetre);
		return bp;
	}
}