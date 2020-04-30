module squareone.common.terrain.basic.chunk;

import squareone.common.voxel;
import squareone.common.terrain.position;
import std.experimental.allocator.mallocator;
import core.atomic;

@trusted:

class Chunk :
	IVoxelBuffer,
	ILoadableVoxelBuffer,
	IReadonlyVoxelBuffer,
	IMeshableVoxelBuffer,
	ICompressableVoxelBuffer
{
	protected ChunkPosition position_;
	@property ChunkPosition position() const { return position_; }
	@property void position(ChunkPosition n)
	{
		position_ = n;
		//transform = Transform(n.toVec3f);
	}

	protected Voxel[] voxelData;
	protected ubyte[] _compressedData;

	this(const VoxelRegistry registry) 
	{
		_meshBlocking.length = registry.processorCount;
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

		_readonlyRefCount = 0;

        if(voxelData !is null)
            deallocateVoxelData();
        if(_compressedData !is null)
            deallocateCompressedData();

        voxels = cast(Voxel[])Mallocator.instance.allocate(dimensionsTotal ^^ 3 * Voxel.sizeof);
        voxels[] = Voxel.init;
    }

	void deinitialise() 
	{
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