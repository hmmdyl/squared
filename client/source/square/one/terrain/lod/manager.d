module square.one.terrain.lod.manager;

import square.one.terrain.chunk;
import square.one.terrain.lod.chunk;
import square.one.terrain.voxel;
import square.one.terrain.resources;
import square.one.terrain.noisegen;
import square.one.terrain.lod.util;

import square.one.utils.objpool;

import std.exception;
import containers.hashmap;
import containers.unrolledlist;

import gfm.math;

alias createNoiseGeneratorFunc = NoiseGenerator delegate();

struct LodTerrainManagerCreateInfo {
    uint lodLevels;
    uint[] chunkDistPerLodLevel;

    createNoiseGeneratorFunc createNoiseGenerator;
    uint noiseGeneratorThreadCount;

    Resources resources;

    static LodTerrainManagerCreateInfo createDefault(Resources resources) {
        LodTerrainManagerCreateInfo info;
        info.lodLevels = 4;
        info.chunkDistPerLodLevel = [4, 12, 28, 60];
        info.createNoiseGenerator = () { return new DefaultNoiseGenerator; };
        info.resources = resources;
        info.noiseGeneratorThreadCount = 2;
        return info;
    }
}

final class LodTerrainManager {
    private HashMap!(ChunkPosition, LodChunk)[] chunks;

    private UnrolledList!LodChangeCommand splitCommands;
    private UnrolledList!LodChangeCommand mergeCommands;
    
    const uint numLodLevels;
    const uint[] lodBoundaries;
    Resources resources;

    private createNoiseGeneratorFunc _createNoiseGenerator;
    private NoiseGeneratorManager noiseGenerator;

    private ObjectPool!LodChunk chunkReservePool;

    this(TerrainManagerCreateInfo createInfo) {
        numLodLevels = createInfo.lodLevels;
        lodBoundaries = createInfo.chunkDistPerLodLevel;
        _createNoiseGenerator = createInfo.createNoiseGenerator;
        noiseGenerator = new NoiseGeneratorManager(resources, createInfo.noiseGeneratorThreadCount, 
            _createNoiseGenerator);

        chunks = new HashMap!(ChunkPosition, LodChunk)[numLodLevels];
        
        chunkReservePool = new ObjectPool!LodChunk(() { return new LodChunk(resources); }, 512, true);
    }

    vec3f localisingCoord;

    void runManager() {
        ChunkPosition cameraPosition = ChunkPosition.fromVec3f(localisingCoord);

        addChunks(cameraPosition);
        findLodChanges(cameraPosition);
        removeChunks(cameraPosition);
    }

    private void addChunks(ChunkPosition cam) {
        void addChunksForLod(int lod) {
            vec3i lower = vec3i(
                cam.x - lodBoundaries[lod],
                cam.y - lodBoundaries[lod],
                cam.z - lodBoundaries[lod]
            );
            vec3i upper = vec3i(
                cam.x + lodBoundaries[lod],
                cam.y + lodBoundaries[lod],
                cam.z + lodBoundaries[lod]
            );

            const int bs = LodLevels[lod];

            for(int x = lower.x; x < upper.x; x += bs) {
                for(int y = lower.y; y < upper.y; y += bs) {
                    for(int z = lower.z; z < upper.z; z += bs) {
                        // notice: may conflict with isInLod(...);

                        ChunkPosition cp = ChunkPosition(x, y, z);
                        LodChunk* cg = cp in chunks[lod];
                        if(cg !is null) {
                            if(cg.pendingRemove)
                                cg.pendingRemove = false;
                            continue;
                        }

                        LodChunk c = chunkReservePool.get();
                        c.initialise(cp);
                        c.lod = lod;
                        c.blockskip = LodLevels[lod].blockskip;
                        c.needsData = true;

                        chunks[lod].insert(cp, c);
                    }
                }
            }
        }

        foreach(int lod; 0 .. numLodLevels)
            addChunksForLod(lod);
    }

    private void findLodChanges(ChunkPosition cam) {
        foreach(HashMap!(ChunkPosition, LodChunk) lodArr; chunks[1..$]) {
            foreach(ref LodChunk chunk; lodArr) {
                int lod = getLodLevel(chunk.position, cam);
                
                ChunkPosition[8] subOctants;
                getSubChunkPositions(chunk.position, chunk.lod, subOctants);

                LodChunk[8] subChunks;
                bool anyNull = false;
                foreach(int i, ChunkPosition subOctant; subOctants) {
                    LodChunk* getter = chunks[chunk.lod - 1];
                    subChunks[i] = *getter;
                    if(getter is null)
                        anyNull = true;
                }

                if(anyNull) continue;

                if(lod < chunk.lod) {
                    // split comm
                    LodChangeCommand lcc = LodChangeCommand(chunk, subChunks);
                    splitCommands.insertBack(lcc);
                }
                else if(!anyNull) {
                    // merge comm
                    LodChangeCommand lcc = LodChangeCommand(chunk, subChunks);
                    mergeCommands.insertBack(lcc);
                }
                // else nothing
            }
        }
    }

    private void executeLodChanges() {
        for(int i = 0; i < mergeCommands.length; i++) {
            LodChangeCommand lcc = mergeCommands.back;
            mergeCommands.popBack();

            foreach(LodChunk sc; lcc.smaller) {

            }
        }
    }

    private bool canRemoveChunk(LodChunk c) {
        return !(c.needsData || c.dataLoadBlocking || c.dataLoadCompleted ||
            c.needsMesh || c.isAnyMeshBlocking);
    }

    private void removeChunks(ChunkPosition cam) {
        foreach(LodChunk chunk; chunks[numLodLevels - 1]) {
            if(!isInLod(chunk.position, cam, numLodLevels - 1)) {
                if(chunk.needsData || chunk.dataLoadBlocking || chunk.dataLoadCompleted ||
                    chunk.needsMesh || chunk.isAnyMeshBlocking)
                    chunk.pendingRemove = true;
                else {
                    foreach(int processorID; 0 .. resources.processorCount)
                        resources.getProcessor(processorID).removeChunk(chunk);

                    chunks[numLodLevels - 1].remove(chunk.position);
                    chunk.deinitialise();
                    chunkReservePool.give(chunk);
                }
            }
        }
    }

    @property createNoiseGeneratorFunc createNoiseGenerator() { return _createNoiseGenerator; }

    @property ulong numChunks() {
        ulong i;
        foreach(clod; chunks) i += clod.length;
        return i;
    }

    @property ulong numChunks(int lod)
    in { assert(lod < chunks.length); }
    body { return chunks[lod].length; }

    bool isInLod(ChunkPosition cp, ChunkPosition cam, int lod) {
        int nx = cam.x - lodBoundaries[lod];
        int ny = cam.y - lodBoundaries[lod];
        int nz = cam.z - lodBoundaries[lod];
        int px = cam.x + lodBoundaries[lod];
        int py = cam.y + lodBoundaries[lod];
        int pz = cam.z + lodBoundaries[lod];

        return cp.x >= nx && cp.x < px &&
            cp.y >= ny && cp.y < py &&
            cp.z >= nz && cp.z < pz;
    }

    void getSubChunkPositions(ChunkPosition pos, int levelOfDetail, ref ChunkPosition[8] sub) {
        enforce(levelOfDetail > 0, "Level of detail must be greater than 0");
        
        const int halfDiammeter = LodLevels[levelOfDetail].chunkSize / 2;
        
        sub[0] = ChunkPosition(pos.x, pos.y, pos.z);
        sub[1] = ChunkPosition(pos.x, pos.y, pos.z + halfDiammeter);
        sub[2] = ChunkPosition(pos.x + halfDiammeter, pos.y, pos.z);
        sub[3] = ChunkPosition(pos.x + halfDiammeter, pos.y, pos.z + halfDiammeter);

        sub[4] = ChunkPosition(pos.x, pos.y + halfDiammeter, pos.z);
        sub[5] = ChunkPosition(pos.x, pos.y + halfDiammeter, pos.z + halfDiammeter);
        sub[6] = ChunkPosition(pos.x + halfDiammeter, pos.y + halfDiammeter, pos.z);
        sub[7] = ChunkPosition(pos.x + halfDiammeter, pos.y + halfDiammeter, pos.z + halfDiammeter);
    }

    int getLodLevel(ChunkPosition cp, ChunkPosition cam) {
        foreach(int lod; 0 .. numLodLevels) {
            int nx = cam.x - lodBoundaries[lod];
            int ny = cam.y - lodBoundaries[lod];
            int nz = cam.z - lodBoundaries[lod];
            int px = cam.x + lodBoundaries[lod];
            int py = cam.y + lodBoundaries[lod];
            int pz = cam.z + lodBoundaries[lod];

            if(cp.x >= nx && cp.x < px &&
                cp.y >= ny && cp.y < py &&
                cp.z >= nz && cp.z < pz)
                return lod;
        }

        return -1;
    }
}

final class LtmRenderer {
    LodTerrainManager manager;

    this(LodTerrainManager manager) {
        this.manager = manager;
    }
}

final class LtmCommandDistributor {

}

final class LtmVoxelBufferHandler {

}