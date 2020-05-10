module squareone.common.content.voxel.vegetation.processor;

import squareone.common.content.voxel.vegetation.types;
import squareone.common.content.voxel.vegetation.mesher;
import squareone.common.voxel;
import squareone.common.meta;
import moxane.core;
import moxane.utils.pool;

abstract class VegetationProcessorBase : IProcessor
{
	protected ubyte id_;
	@property ubyte id() const { return id_; }
	@property void id(ubyte n) { id_ = n; }

	struct MeshResult
	{
		MeshOrder order;
		MeshBuffer buffer;
	}

	Pool!MeshBuffer meshBufferPool;
    Channel!MeshResult meshResults;

	Moxane moxane;
	VoxelRegistry registry;

	mixin(VoxelContentQuick!("squareOne:voxel:processor:vegetation", "", name, dylanGraham));

	this(Moxane moxane, VoxelRegistry registry)
	in { assert(moxane !is null); assert(registry !is null); }
	do {
		this.moxane = moxane;
		this.registry = registry;
	}	

	abstract void finaliseResources();
	abstract void removeChunk(IMeshableVoxelBuffer voxelBuffer);
	abstract void updateFromManager();

	abstract IVegetationVoxelTexture getTexture(ushort id);
	abstract IVegetationVoxelTexture getTexture(string technical);
	abstract IVegetationVoxelMesh getMesh(MeshID id);
	abstract IVegetationVoxelMaterial getMaterial(MaterialID id);

	@property size_t minMeshers() const { return 2; }
	IMesher requestMesher(IChannel!MeshOrder source) { return new Mesher(this, source); }
	void returnMesher(IMesher m) {}
}