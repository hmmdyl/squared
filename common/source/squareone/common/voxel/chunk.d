module squareone.common.voxel.chunk;

import squareone.common.voxel.voxel;

public import moxane.core : AtomicTransform;

import dlib.math.vector;

import std.math;

@safe:

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
	@property ref AtomicTransform transform();
	@property void transform(ref AtomicTransform);

	@property ref void*[] drawData();
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

	@property ref ubyte[] compressedData();
	@property void compressedData(ubyte[]);
	void deallocateCompressedData();
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

