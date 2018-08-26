module square.one.terrain.chunk;

import square.one.terrain.voxel;
import square.one.terrain.manager;
import square.one.terrain.rlecompressor;
import square.one.utils.disposable;

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

interface IVoxelBuffer {
	@property int dimensionsProper();
	@property int dimensionsTotal();
	@property int overrun();

	@property bool hasData();
	@property void hasData(bool);

	@property int lod();
	@property void lod(int);
	@property int blockskip();
	@proeprty void blockskip(int);

	@property int airCount();
	@property void airCount(int);

	Voxel get(int x, int y, int z);
	Voxel getRaw(int x, int y, int z);
	void set(int x, int y, int z, Voxel voxel);
	void setRaw(int x, int y, int z, Voxel voxel);
}

interface ILoadableVoxelBuffer : IVoxelBuffer {
	@property bool needsData();
	@property void needsData(bool);
	@property bool dataLoadBlocking();
	@property void dataLoadBlocking(bool);
	@property bool dataLoadCompleted();
	@property void dataLoadCompleted(bool);
}

interface IRenderableVoxelBuffer : IVoxelBuffer {
	@property ref void*[] renderData();
}

interface IMeshableVoxelBuffer : IVoxelBuffer {
	@property bool needsMesh();
	@property void needsMesh(bool);
	@property bool meshBlocking(size_t processorID);
	@property void meshBlocking(bool v, size_t processorID);
	@property bool isAnyMeshBlocking();
}

interface ICompressableVoxelBuffer : IVoxelBuffer {
	@property bool isCompressed();
	@property void isCompressed(bool);

	@property ref Voxel[] voxels();
	@property void voxels(Voxel[]);
	void deallocateVoxelData();

	@property ref void* compressedData();
	@property void compressedData(void*);
	void deallocateCompressedData();
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

struct ChunkPosition {
	int x, y, z;

	this(int x, int y, int z) {
		this.x = x;
		this.y = y;
		this.z = z;
	}

	size_t toHash() const @safe pure nothrow {
		size_t hash = 17;
		hash = hash * 31 + x;
		hash = hash * 31 + y;
		hash = hash * 31 + z;
		return hash;
	}

	bool opEquals(ref const ChunkPosition other) const @safe pure nothrow {
		return other.x == x && other.y == y && other.z == z;
	}

	vec3f toVec3f() {
		return vec3f(x * chunkDimensionsMetres, y * chunkDimensionsMetres, z * chunkDimensionsMetres);
	}

	static ChunkPosition fromVec3f(vec3f v) {
		return ChunkPosition(cast(int)(v.x * invChunkDimensionsMetres), cast(int)(v.y * invChunkDimensionsMetres), cast(int)(v.z * invChunkDimensionsMetres));
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