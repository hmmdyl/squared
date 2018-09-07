﻿module square.one.terrain.basic.chunk;

public import square.one.terrain.chunk;
import square.one.terrain.resources;

import moxana.entity.transform;

import gfm.math;

struct BasicChunk 
{
    Chunk chunk;
    private ChunkPosition _position;
    @property ChunkPosition position() { return _position; }
    @property void position(ChunkPosition n) {
        _position = n;
        Transform transform = Transform();
        transform.position = n.toVec3f;
        transform.rotation = vec3f(0);
        transform.scale = vec3f(1);
        chunk.transform = transform;
    }

    this(Chunk chunk, ChunkPosition position) 
    {
        this.chunk = chunk;
        this.position = position;
    }
}