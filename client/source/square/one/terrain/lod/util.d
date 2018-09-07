module square.one.terrain.lod.util;

import square.one.terrain.chunk : ChunkPosition;

/*struct LodChangeCommand {
    enum ChangeType : byte {
        merge,
        split
    }

    LodChunk larger;
    LodChunk[8] smaller;
    ChangeType changeType;

    this(LodChunk larger, LodChunk s0, LodChunk s1, LodChunk s2, LodChunk s3, 
    LodChunk s4, LodChunk s5, LodChunk s6, LodChunk s7, ChangeType type) {
        this.larger = larger;
        smaller[0] = s0;
        smaller[1] = s1;
        smaller[2] = s2;
        smaller[3] = s3;
        smaller[4] = s4;
        smaller[5] = s5;
        smaller[6] = s6;
        smaller[7] = s7;
        changeType = type;
    }

    this(Chunk larger, LodChunk[8] smaller, ChangeType type) {
        this.larger = larger;
        this.smaller = smaller;
        changeType = type;
    }
}*/

struct LodLevel {
	int blockskip;
	int lod;
	int chunkSize;

	this(int blockskip, int lod, int chunkSize) {
		this.blockskip = blockskip;
		this.lod = lod;
		this.chunkSize = chunkSize;
	}

	LodLevel dup() const {
		LodLevel l;
		l.blockskip = blockskip;
		l.lod = lod;
		l.chunkSize = chunkSize;
		return l;
	}
}

static immutable LodLevel[] LodLevels = [
	LodLevel(1, 0, 1),
	LodLevel(2, 1, 2),
	LodLevel(4, 2, 4),
	LodLevel(8, 3, 8),
	LodLevel(16, 4, 16)
];

ChunkPosition acrossLod(ChunkPosition cp, int desiredLod) {
	int ifloordiv(int n, int divisor) {
		if(n >= 0)
			return n / divisor;
		else
			return ~(~n / divisor);
	}
	
	int cs = LodLevels[desiredLod].chunkSize;
	ChunkPosition ncp;
	ncp.x = ifloordiv(cp.x, cs) * cs;
	ncp.y = ifloordiv(cp.y, cs) * cs;
	ncp.z = ifloordiv(cp.z, cs) * cs;
	return ncp;
}