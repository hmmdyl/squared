module squareone.client.terrain.basic.chunk;

import squareone.common.terrain.basic;
import squareone.common.terrain.position;
import squareone.common.voxel;

@safe:

class Chunk : squareone.common.terrain.basic.Chunk, IRenderableVoxelBuffer
{
	this(VoxelRegistry registry)
	{
		super(registry);
		_renderData.length = registry.processorCount;
	}

	override void initialise()
	{
		super.initialise();
		foreach(ref void* rd; _renderData)
			rd = null;
	}

	/+override @property void position(ChunkPosition n)
	{
		position_ = n;
		transform = AtomicTransform(n.toVec3f);
	}+/

	private AtomicTransform _transform;
	@property ref AtomicTransform transform() { return _transform; }
	@property void transform(ref AtomicTransform n) { _transform = n; }

    private void*[] _renderData;
    @property ref void*[] drawData() { return _renderData; }
}

struct ReadonlyChunk
{
	package Chunk chunk;

	this(Chunk chunk)
	{
		this.chunk = chunk;
	}

	@property int dimensionsProper() { return chunk.dimensionsProper; }
	@property int dimensionsTotal() { return chunk.dimensionsTotal; }
	@property int overrun() { return chunk.overrun; }
	@property float voxelScale() { return chunk.voxelScale; }

	@property bool hasData() { return chunk.hasData; }
	@property int lod() { return chunk.lod; }
	@property int blockskip() { return chunk.blockskip; }

	@property int solidCount() { return chunk.solidCount; }
	@property int airCount() { return chunk.airCount; }

	@property ref AtomicTransform transform() { return chunk.transform; }
	@property ChunkPosition position() { return chunk.position(); }

	@property int readonlyRefs() { return chunk.readonlyRefs; }

	Voxel get(int x, int y, int z)
	{ return chunk.get(x, y, z); }

	Voxel getRaw(int x, int y, int z)
	{ return chunk.getRaw(x, y, z); }
}