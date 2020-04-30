module squareone.common.terrain.position;

import squareone.common.voxel;
import dlib.math.vector;
import std.math;

@safe:

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

private Vector3i[2][26] getNeighbourBounds(Vector3i[2] function(ChunkNeighbours) @safe fn)
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

	ChunkPosition opBinary(string op)(const ChunkPosition right)
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
