module squareone.terrain.basic.chunk;

import squareone.voxel;
import squareone.terrain.basic.manager;
import dlib.math.vector;
import moxane.core.transformation;

class BasicChunk : Chunk
{
	private ChunkPosition position_;
	@property ChunkPosition position() const { return position_; }
	@property void position(ChunkPosition n)
	{
		position_ = n;
		transform = Transform(n.toVec3f);
	}

	this(Resources r) { super(r); }
}

/+struct BasicChunk 
{
    Chunk chunk;
    private ChunkPosition _position;
    @property ChunkPosition position() { return _position; }
    @property void position(ChunkPosition n) {
        _position = n;
        Transform transform = Transform();
        transform.position = n.toVec3f;
        transform.rotation = Vector3f(0, 0, 0);
        transform.scale = Vector3f(1, 1, 1);
        chunk.transform = transform;
    }

    this(Chunk chunk, ChunkPosition position) 
    {
        this.chunk = chunk;
        this.position = position;
    }
}+/

struct BasicChunkReadonly
{
	package BasicChunk chunk;

	this(BasicChunk chunk)
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

	@property ref Transform transform() { return chunk.transform; }
	@property ChunkPosition position() const { return chunk.position; }

	@property int readonlyRefs() { return chunk.readonlyRefs; }

	Voxel get(int x, int y, int z)
	{ return chunk.get(x, y, z); }

	Voxel getRaw(int x, int y, int z)
	{ return chunk.getRaw(x, y, z); }
}