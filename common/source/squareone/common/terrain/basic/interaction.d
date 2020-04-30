module squareone.common.terrain.basic.interaction;

import moxane.core;
import moxane.utils.maybe;

import squareone.common.voxel;
import squareone.common.terrain.position;
import squareone.common.terrain.basic.chunk;

@safe:

interface IVoxelInteraction
{
	Maybe!Voxel get(BlockPosition pos);
	Maybe!Voxel get(ChunkPosition cp, BlockOffset off);

	void set(Voxel voxel, BlockPosition pos);
	void set(Voxel voxel, ChunkPosition cp, BlockOffset offset);
}

interface IChunkInteraction(TChunk, TReadonlyChunk)
{
	TChunk borrow(ChunkPosition cp);
	Maybe!TReadonlyChunk borrowReadonly(ChunkPosition cp);
	void give(TChunk chunk);
	void give(TReadonlyChunk rc);
}