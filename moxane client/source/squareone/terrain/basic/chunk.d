module squareone.terrain.basic.chunk;

import squareone.voxel.chunk;
import dlib.math.vector;
import moxane.graphics.transformation;

struct BasicChunk 
{
    Chunk chunk;
    private ChunkPosition _position;
    @property ChunkPosition position() { return _position; }
    @property void position(ChunkPosition n) {
        _position = n;
        Transform transform = Transform();
        transform.position = n.toVec3f;
        transform.rotation = Vector3f(0);
        transform.scale = Vector3f(1);
        chunk.transform = transform;
    }

    this(Chunk chunk, ChunkPosition position) 
    {
        this.chunk = chunk;
        this.position = position;
    }
}