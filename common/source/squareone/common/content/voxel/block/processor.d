module squareone.common.content.voxel.block.processor;

import squareone.common.content.voxel.block.mesher;
import squareone.common.voxel;
import squareone.common.meta;

import moxane.core;

import std.container.dlist;

@safe:

abstract class BlockProcessorBase : IProcessor
{
	private ubyte id_;
	@property ubyte id() const { return id_; }
	@property void id(ubyte n) { id_ = n; }

	struct MeshResult
	{
		MeshOrder order;
		MeshBuffer buffer;
	}

	MeshBufferHost meshBufferHost;
	DList!MeshResult uploadQueue;
	Object uploadSyncObj;

	Moxane moxane;
	VoxelRegistry registry;

	mixin(VoxelContentQuick!("squareOne:voxel:processor:block", "", name, dylanGraham));

	abstract void finaliseResources();
	abstract void removeChunk(IMeshableVoxelBuffer voxelBuffer);
	abstract void updateFromManager();

	@property size_t minMeshers() const { return 2; }
	IMesher requestMesher(IChannel!MeshOrder source) { return new Mesher(this, registry, meshBufferHost, source); }
	void returnMesher(IMesher m) {}
}