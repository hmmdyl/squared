module square.one.terrain.manager;

public import square.one.terrain.chunk;
public import square.one.terrain.voxel;
public import square.one.terrain.resources;

import square.one.utils.objpool;

import moxana.graphics.frustum;
import moxana.graphics.effect;
import moxana.graphics.rendercontext;
import moxana.graphics.rh;

import square.one.terrain.noisegen;

import derelict.opengl3.gl3;
import gfm.math;
import containers.hashmap;

import core.thread;
import core.sync.mutex;
import std.math;
import std.datetime.stopwatch;
import std.container.dlist;
import std.algorithm.sorting;

struct SetBlockCommand {
	long bx, by, bz;
	Voxel over;
}

alias createNoiseGeneratorFunc = NoiseGenerator delegate();

struct TerrainManagerCreateInfo {
	uint chunkAddRange;
	uint chunkRemoveRange;
	bool circularAdd;
	createNoiseGeneratorFunc createNoiseGenerator;
	Resources resources;

	uint noiseGeneratorThreadCount;

	static TerrainManagerCreateInfo createDefault(Resources res) {
		TerrainManagerCreateInfo info;
		info.chunkAddRange = 8;
		info.chunkRemoveRange = 10;
		info.circularAdd = true;
		info.createNoiseGenerator = () { return new DefaultNoiseGenerator; };
		info.resources = res;
		info.noiseGeneratorThreadCount = 2;
		return info;
	}
}

final class TerrainManager : IRenderHandler {
	private Mutex renderChunksMutex;
	private HashMap!(ChunkPosition, Chunk) chunks;
	private HashMap!(ChunkPosition, Chunk) renderChunks;

	@property ulong numChunks() {  return chunks.length;
	}

	private ObjectPool!Chunk cpool;

	Resources resources;
	const int addRange;
	const int removeRange;
	const bool circularAdd;
	private createNoiseGeneratorFunc createNoiseGenerator_;
	@property createNoiseGeneratorFunc createNoiseGenerator() { return createNoiseGenerator_; }

	private Thread updater;

	private Object setBlockCommandsSync = new Object();
	private DList!SetBlockCommand setBlockCommands;

	NoiseGeneratorManager ng;

	private vec3f cameraPosition_;
	private vec3f previousCameraPosition_;

	@property vec3f cameraPosition() { return cameraPosition_; }
	@property void cameraPosition(vec3f n) {
		previousCameraPosition_ = cameraPosition_;
		cameraPosition_ = n;
	}
	@property vec3f previousCameraPosition() { return previousCameraPosition_; }

	@property ChunkPosition cameraChunkPos() { return ChunkPosition.fromVec3f(cameraPosition_); }

	this(TerrainManagerCreateInfo info, vec3f cameraPosition) {
		resources = info.resources;
		resources.finaliseResources;
		addRange = cast(int)info.chunkAddRange;
		removeRange = cast(int)info.chunkRemoveRange;
		circularAdd = info.circularAdd;
		createNoiseGenerator_ = info.createNoiseGenerator;

		cpool = ObjectPool!Chunk(() { return new Chunk(this); }, 8192, true);

		ng = new NoiseGeneratorManager(resources, info.noiseGeneratorThreadCount, createNoiseGenerator_);

		renderChunksMutex = new Mutex();

		this.cameraPosition_ = cameraPosition;
		this.previousCameraPosition_ = cameraPosition;

		/*updater = new Thread(&update);
		updater.isDaemon = true;
		updater.start();*/
	}

	bool isLoadingTime = true;

	double updateTime;

	private StopWatch updateSw;

	void update() {
		int numInitialMeshed = 0;

		bool r = true;
		while(r) {
			updateTime = updateSw.peek.total!"nsecs"() / 1_000_000.0;
			updateSw.reset;

			r = false;
			//Thread.sleep(dur!"msecs"(2));

			updateSw.start;

			ChunkPosition cp = cameraChunkPos;

			createChunks(cp);

			synchronized(setBlockCommandsSync) {
				while(!setBlockCommands.empty) {
					SetBlockCommand comm = setBlockCommands.front;
					setBlockCommands.removeFront();

					int cx = cast(int)(floor(comm.bx / cast(float)chunkDimensions));
					int cy = cast(int)(floor(comm.by / cast(float)chunkDimensions));
					int cz = cast(int)(floor(comm.bz / cast(float)chunkDimensions));

					int lx = cast(int)(comm.bx - (cx * chunkDimensions));
					int ly = cast(int)(comm.by - (cy * chunkDimensions));
					int lz = cast(int)(comm.bz - (cz * chunkDimensions));

					if(lx < 0) lx = lx + (chunkDimensions - 1);
					if(ly < 0) ly = ly + (chunkDimensions - 1);
					if(lz < 0) lz = lz + (chunkDimensions - 1);

					Chunk* c = ChunkPosition(cx, cy, cz) in chunks;
					if(c is null) continue;

					if(c.isArrayCompressed) {
						c.decompress();
					}

					setBlockOtherChunkOverruns(comm.over, lx, ly, lz, *c);

					c.set(lx, ly, lz, comm.over);

					c.countAir();
					c.needsMesh = true;
				}
			}

			foreach(Chunk chunk; chunks) {
				if(chunk.needsNoise && !chunk.isMeshBlocking) {
					ng.generate(chunk);
				}
				if(chunk.noiseCompleted) {
					chunk.needsMesh = true;
					chunk.noiseCompleted = false;
				}

				if(chunk.needsMesh && !chunk.needsNoise && !chunk.noiseBlocking && !chunk.noiseCompleted) {
					if(chunk.airCount == chunkOverrunDimensionsCubed || chunk.airCount == 0) {}
					else {
						foreach(int procID; 0 .. resources.processorCount) {
							resources.getProcessor(procID).meshChunk(chunk);
						}
					}

					chunk.needsMesh = false;
				}

				//if(!chunk.needsNoise && !chunk.noiseBlocking && !chunk.noiseCompleted && !chunk.needsMesh && !chunk.isMeshBlocking) {
				//	if(!chunk.isArrayCompressed) {
				//		chunk.compress();
				//	}
				//}

				if(!chunkInBounds(cp, chunk.position)) {
					if(chunk.needsNoise || chunk.noiseBlocking || chunk.noiseCompleted ||
						chunk.needsMesh || chunk.isMeshBlocking) {
						chunk.pendingRemove = true;
					}
					else {	
						foreach(int procid; 0 .. resources.processorCount) {
							resources.getProcessor(procid).removeChunk(chunk);
						}

						chunks.remove(chunk.position);
						chunk.deinitialise();
						cpool.give(chunk);
					}
				}
			}

			/*if(renderChunksMutex.tryLock()) {
				foreach(const(ChunkPosition) pos, Chunk chunk; chunks) {
					if((chunk.position in renderChunks) is null) {
						renderChunks[chunk.position] = chunk;
					}
				}
				foreach(const(ChunkPosition) pos, Chunk chunk; renderChunks) {
					if((chunk.position in chunks) is null) {
						renderChunks.remove(chunk.position);
					}
				}

				updateMs = sw.peek().total!"nsecs"() / 1_000_000f;
				sw.reset();

				renderChunksMutex.unlock();
			}*/

			if(isLoadingTime) {
				if(numberOfChunksInMeshingOrNoise == 0)
					isLoadingTime = false;
			}

			updateSw.stop;
		}
	}

	private @property int numberOfChunksInMeshingOrNoise() {
		int i = 0;
		foreach(Chunk c; chunks) {
			if(c.needsNoise || c.noiseBlocking || c.needsMesh || c.isMeshBlocking)
				i++;
		}
		return i;
	}

	bool chunkInBounds(ChunkPosition cp, ChunkPosition pos) {
		return 
			pos.x >= cp.x - removeRange && pos.x < cp.x + removeRange &&
				pos.y >= cp.y - removeRange && pos.y < cp.y + removeRange &&
				pos.z >= cp.z - removeRange && pos.z < cp.z + removeRange;
	}

	private auto chunkDistanceComparer(ChunkPosition x, ChunkPosition y) {
		double x1 = x.toVec3f.length - cameraPosition_.length;
		double y1 = y.toVec3f.length - cameraPosition_.length;

		return x1 < y1;
	}

	private void createChunks(ChunkPosition cp) {
		import std.stdio;
		//writeln("tits ", addRange, " ", cameraPosition, " ", cp);

		//if(cameraPosition_ == previousCameraPosition_ && !isLoadingTime)
		//	return;

		for(int x = cp.x - addRange; x < cp.x + addRange; x++) {
			for(int y = cp.y - addRange; y < cp.y + addRange; y++) {
				for(int z = cp.z - addRange; z < cp.z + addRange; z++) {

					ChunkPosition c = ChunkPosition(x, y, z);
					Chunk* getter = (c in chunks);
					if(getter is null) {
						Chunk ch = cpool.get();
						ch.initialise(c);
						ch.needsNoise = true;
						ch.lod = 0;
						ch.blockskip = 1;
						chunks[c] = ch;
					}
					else {
						if(getter.pendingRemove) 
							getter.pendingRemove = false;
					}
				}
			}
		}

	}

	int renderCount = 0;

	void shadowDepthMapPass(RenderContext rc, ref LocalRenderContext lrc) {
		renderPhysical(rc, lrc);
	}
	void renderPostPhysical(RenderContext rc, ref LocalRenderContext lrc) {}
	void ui(RenderContext rc) {}

	void renderPhysical(RenderContext rc, ref LocalRenderContext lrc) {
		renderCount = 0;

		mat4f vp = lrc.perspective.matrix * lrc.view;
		SqFrustum!float f = SqFrustum!float(vp.transposed());

		renderChunksMutex.lock();

		foreach(ubyte procID; 0 .. resources.processorCount) {
			IProcessor proc = resources.getProcessor(procID);

			proc.prepareRender(rc);

			foreach(Chunk chunk; chunks) {
				// ***** AS OF 31/12/17 *****
				// TODO: Implemnt frustum culling.

				vec3f centre = chunk.position.toVec3f() + vec3f(4f);

				//if(f.containsSphere(centre, 5.66)) {
					proc.render(chunk, lrc);
					renderCount++;
				//}
			}

			proc.endRender();
		}

		import std.stdio;
		//writeln(renderCount, " ", numChunks);

		renderChunksMutex.unlock();
	}

	void addSetBlockCommand(SetBlockCommand comm) {
		synchronized(setBlockCommandsSync) {
			setBlockCommands.insertBack(comm);
		}
	}

	Voxel getVoxel(vec3l blockPos, out bool got) {
		int cx = cast(int)(floor(blockPos.x / cast(float)chunkDimensions));
		int cy = cast(int)(floor(blockPos.y / cast(float)chunkDimensions));
		int cz = cast(int)(floor(blockPos.z / cast(float)chunkDimensions));

		int lx = cast(int)(blockPos.x - (cx * chunkDimensions));
		int ly = cast(int)(blockPos.y - (cy * chunkDimensions));
		int lz = cast(int)(blockPos.z - (cz * chunkDimensions));

		if(lx < 0) lx = lx + (chunkDimensions - 1);
		if(ly < 0) ly = ly + (chunkDimensions - 1);
		if(lz < 0) lz = lz + (chunkDimensions - 1);

		Chunk* c = ChunkPosition(cx, cy, cz) in chunks;
		if(c is null) {
			got = false;
			return Voxel();
		}

		if(!c.isInitialised) {
			got = false;
			return Voxel();
		}

		if(c.isArrayCompressed) {
			c.decompress();
		}
		c.lastRefSw.reset();
		if(!c.lastRefSw.running)
			c.lastRefSw.start();

		got = true;

		return c.get(lx, ly, lz);
	}

	// TODO: Implement PxPz, PxNz, NxPz, NxNz
	private immutable vec3i[][] chunkOffsets = [
		// Nx Ny Nz
		[vec3i(-1, 0, 0), vec3i(0, -1, 0), vec3i(0, 0, -1), vec3i(-1, -1, 0), vec3i(-1, 0, -1), vec3i(0, -1, -1), vec3i(-1, -1, -1)],
		// Nx Ny Pz
		[vec3i(-1, 0, 0), vec3i(0, -1, 0), vec3i(0, 0, 1), vec3i(-1, -1, 0), vec3i(-1, 0, 1), vec3i(0, -1, 1), vec3i(-1, -1, 1)],
		// Nx Ny 
		[vec3i(-1, 0, 0), vec3i(0, -1, 0), vec3i(-1, -1, 0)],
		// Nx Py Nz
		[vec3i(-1, 0, 0), vec3i(0, 1, 0), vec3i(0, 0, -1), vec3i(-1, 1, 0), vec3i(-1, 0, -1), vec3i(0, 1, -1), vec3i(-1, 1, -1)],
		// Nx Py Pz
		[vec3i(-1, 0, 0), vec3i(0, 1, 0), vec3i(0, 0, 1), vec3i(-1, 1, 0), vec3i(-1, 0, 1), vec3i(0, 1, 1), vec3i(-1, 1, 1)],
		// Nx Py
		[vec3i(-1, 0, 0), vec3i(0, 1, 0), vec3i(-1, 1, 0)],
		// Nx Nz
		[vec3i(-1, 0, 0), vec3i(0, 0, -1), vec3i(-1, 0, -1)],
		// Nx Pz
		[vec3i(-1, 0, 0), vec3i(0, 0, 1), vec3i(-1, 0, 1)],
		// Nx
		[vec3i(-1, 0, 0)],
		// Px Ny Nz
		[vec3i(1, 0, 0), vec3i(0, -1, 0), vec3i(0, 0, -1), vec3i(1, -1, 0), vec3i(1, 0, -1), vec3i(0, -1, -1), vec3i(1, -1, -1)],
		// Px Ny Pz
		[vec3i(1, 0, 0), vec3i(0, -1, 0), vec3i(0, 0, 1), vec3i(1, -1, 0), vec3i(1, 0, 1), vec3i(0, -1, 1), vec3i(1, -1, 1)],
		// Px Ny 
		[vec3i(1, 0, 0), vec3i(0, -1, 0), vec3i(1, -1, 0)],
		// Px Py Nz
		[vec3i(1, 0, 0), vec3i(0, 1, 0), vec3i(0, 0, -1), vec3i(1, 1, 0), vec3i(1, 0, -1), vec3i(0, 1, -1), vec3i(1, 1, -1)],
		// Px Py Pz
		[vec3i(1, 0, 0), vec3i(0, 1, 0), vec3i(0, 0, 1), vec3i(1, 1, 0), vec3i(1, 0, 1), vec3i(0, 1, 1), vec3i(1, 1, 1)],
		// Px Py
		[vec3i(1, 0, 0), vec3i(0, 1, 0), vec3i(1, 1, 0)],
		// Nx Nz
		[vec3i(1, 0, 0), vec3i(0, 0, -1), vec3i(1, 0, -1)],
		// Nx Pz
		[vec3i(1, 0, 0), vec3i(0, 0, 1), vec3i(1, 0, 1)],
		// Px
		[vec3i(1, 0, 0)],
		// Ny Nz
		[vec3i(0, -1, 0), vec3i(0, 0, -1), vec3i(0, -1, -1)],
		// Ny Pz
		[vec3i(0, -1, 0), vec3i(0, 0, 1), vec3i(0, -1, 1)],
		// Ny
		[vec3i(0, -1, 0)],
		// Py Nz
		[vec3i(0, 1, 0), vec3i(0, 0, -1), vec3i(0, 1, -1)],
		// Py Pz
		[vec3i(0, 1, 0), vec3i(0, 0, 1), vec3i(0, 1, 1)],
		// Py
		[vec3i(0, 1, 0)],
		// Nz
		[vec3i(0, 0, -1)],
		// Pz
		[vec3i(0, 0, 1)]
	];

	private void setBlockOtherChunkOverruns(Voxel voxel, int x, int y, int z, Chunk host) 
	in {
		assert(x >= 0 && x < chunkDimensions);
		assert(y >= 0 && y < chunkDimensions);
		assert(z >= 0 && z < chunkDimensions);
	}
	body {
		if(x == 0) {
			if(y == 0) {
				if(z == 0) {
					foreach(vec3i off; chunkOffsets[0])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == chunkDimensions - 1) {
					foreach(vec3i off; chunkOffsets[1])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(vec3i off; chunkOffsets[2])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
			else if(y == chunkDimensions - 1) {
				if(z == 0) {
					foreach(vec3i off; chunkOffsets[3])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == chunkDimensions - 1) {
					foreach(vec3i off; chunkOffsets[4])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(vec3i off; chunkOffsets[5])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
			else {
				if(z == 0) {
					foreach(vec3i off; chunkOffsets[6])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == chunkDimensions - 1) {
					foreach(vec3i off; chunkOffsets[7]) 
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(vec3i off; chunkOffsets[8])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
		}
		else if(x == chunkDimensions - 1) {
			if(y == 0) {
				if(z == 0) {
					foreach(vec3i off; chunkOffsets[9])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == chunkDimensions - 1) {
					foreach(vec3i off; chunkOffsets[10])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(vec3i off; chunkOffsets[11])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
			else if(y == chunkDimensions - 1) {
				if(z == 0) {
					foreach(vec3i off; chunkOffsets[12])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == chunkDimensions - 1) {
					foreach(vec3i off; chunkOffsets[13])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(vec3i off; chunkOffsets[14])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
			else {
				if(z == 0) {
					foreach(vec3i off; chunkOffsets[15])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else if(z == chunkDimensions - 1) {
					foreach(vec3i off; chunkOffsets[16]) 
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
				else {
					foreach(vec3i off; chunkOffsets[17])
						setBlockForChunkOffset(off, host, x, y, z, voxel);
					return;
				}
			}
		}

		if(y == 0) {
			if(z == 0) {
				foreach(vec3i off; chunkOffsets[18])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
			else if(z == chunkDimensions - 1) {
				foreach(vec3i off; chunkOffsets[19])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
			else {
				foreach(vec3i off; chunkOffsets[20])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
		}
		else if(y == chunkDimensions - 1) {
			if(z == 0) {
				foreach(vec3i off; chunkOffsets[21])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
			else if(z == chunkDimensions - 1) {
				foreach(vec3i off; chunkOffsets[22])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
			else {
				foreach(vec3i off; chunkOffsets[23])
					setBlockForChunkOffset(off, host, x, y, z, voxel);
				return;
			}
		}

		if(z == 0) {
			foreach(vec3i off; chunkOffsets[24])
				setBlockForChunkOffset(off, host, x, y, z, voxel);
			return;
		}
		else if(z == chunkDimensions - 1) {
			foreach(vec3i off; chunkOffsets[25])
				setBlockForChunkOffset(off, host, x, y, z, voxel);
			return;
		}
	}

	private void setBlockForChunkOffset(vec3i off, Chunk host, int x, int y, int z, Voxel voxel) {
		ChunkPosition cp = ChunkPosition(host.position.x + off.x, host.position.y + off.y, host.position.z + off.z);
		Chunk* c = cp in chunks;

		assert(c !is null);

		int newX = x + (-off.x * chunkDimensions);
		int newY = y + (-off.y * chunkDimensions);
		int newZ = z + (-off.z * chunkDimensions);

		c.set(newX, newY, newZ, voxel);
		c.countAir();
		c.needsMesh = true;
	}
}