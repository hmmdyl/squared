module square.one.terrain.lod.chunk;

import square.one.terrain.chunk;
import square.one.terrain.resources;

import std.experimental.allocator.mallocator;
import core.atomic;

class LodChunk : IVoxelBuffer, IRenderableVoxelBuffer, IMeshableVoxelBuffer, ILoadableVoxelBuffer, ICompressableVoxelBuffer {
    private Voxel[] voxelData;
    private ubyte[] compressedData;

    ChunkPosition position;

    this(Resources resources) {
        _meshBlocking.length = resources.processorCount;
        _renderData.length = resources.processorCount;
    }

    void initialise(ChunkPosition pos) {
        position = pos;

        needsData = false;
        dataLoadBlocking = false;
        dataLoadCompleted = false;
        needsMesh = false;

        if(voxelData !is null)
            deallocateVoxelData();
        if(compressedData !is null)
            deallocateCompressedData();

        voxels = cast(Voxel[])Mallocator.instance.allocate(memSize);
        voxels[] = Voxel(0, 0, 0, 0);

        foreach(ref rd; renderData)
            rd = null;
    }

    void deinitialise() {
        if(voxelData !is null)
            deallocateVoxelData();
        if(compressedData !is null)
            deallocateCompressedData();

        position = ChunkPosition();
    }

    Voxel get(int x, int y, int z) 
    in { assert(voxelData !is null); }
    body {
        x += blockskip * overrunDimensions;
        y += blockskip * overrunDimensions;
        z += blockskip * overrunDimensions;
        x = x >> _lod;
        y = y >> _lod;
        z = z >> _lod;
        return voxelData[flattenIndex(x, y, z)];
    }

    Voxel getRaw(int x, int y, int z) 
    in { assert(voxelData !is null); }
    body {
        x += overrunDimensions;
        y += overrunDimensions;
        z += overrunDimensions;
        return voxelData[flattenIndex(x, y, z)];
    }
    
    void set(int x, int y, int z, Voxel voxel) 
    in { assert(voxelData !is null); }
    body {
        x += blockskip * overrunDimensions;
        y += blockskip * overrunDimensions;
        z += blockskip * overrunDimensions;
        x = x >> _lod;
        y = y >> _lod;
        z = z >> _lod;
        voxelData[flattenIndex(x, y, z)] = voxel;
    }

    void setRaw(int x, int y, int z, Voxel voxel) 
    in { assert(voxelData !is null); }
    body {
        x += overrunDimensions;
        y += overrunDimensions;
        z += overrunDimensions;
        voxelData[flattenIndex(x, y, z)] = voxel;
    }

    pragma(inline, true)
    @property int dimensionsProper() { return dimensions; }
    pragma(inline, true)
    @property int dimensionsTotal() { return overrunDimensions; }
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

    @property ref void* compressedData() { return compressedData; }
    @property void compressedData(void* v) { compressedData = v; }

    void deallocateCompressedData() {
        assert(compressedData !is null);
        Mallocator.instance.deallocate(compressedData);
        compressedData = null;
    }

    pragma(inline, true)
    static int flattenIndex(int x, int y, int z) {
        return x + overrunDimensions * (y + overrunDimensions * z);
    }

    private shared bool _pendingRemove;
    @property bool pendingRemove() { return atomicLoad(_pendingRemove); }
    @property void pendingRemove(bool n) { atomicStore(_pendingRemove, n); }
}

enum int dimensions = 16;
enum int overrunDimensions = 16 + 2;
enum int voxelOffset = 1;

enum int dimensions3 = dimensions ^^ 3;
enum int overrunDimensions3 = overrunDimensions ^^ 3;

enum int voxelsPerMetre = 4;
enum float voxelScale = 0.25f;

enum float dimensionsMetres = chunkDimensions * voxelScale;
enum float dimensionsInvMetres = 1f / dimensionsMetres;

enum memSize = overrunDimensions3 * Voxel.sizeof;