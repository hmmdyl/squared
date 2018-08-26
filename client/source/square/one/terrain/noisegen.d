﻿module square.one.terrain.noisegen;

import square.one.terrain.chunk;
import square.one.terrain.voxel;
import square.one.terrain.resources;

import containers.cyclicbuffer;

import std.container.array;
import std.conv;

import core.atomic;
import core.sync.condition;
import core.thread;

import moxana.procgen.opensimplexnoise;
import moxana.utils.logger;

import gfm.math;

import accessors;

class NoiseGeneratorManager {
	protected CyclicBuffer!(NoiseGenerator) generators;

	Resources resources;

	private alias createNGDel = NoiseGenerator delegate();
	private createNGDel createNG;

	this(Resources resources, int threadNum, createNGDel createNG) {
		this.resources = resources;
		this.createNG = createNG;

		threadCount = threadNum;
	}

	double averageTime = 0, lowestTime = 0, highestTime = 0;

	private __gshared uint threadCount_ = 0;
	@property uint threadCount() { return threadCount_; }
	@property void threadCount(uint tc) {
		setNumTreads(tc);
		threadCount_ = tc;
	}

	@property uint numBusy() {
		uint n = 0;
		foreach(NoiseGenerator ng; generators) {
			if(ng.busy)
				n++;
		}
		return n;
	}

	private void setNumTreads(uint tc) {
		if(tc < threadCount_) {
			int diff = threadCount_ - tc;
			debug writeLog(LogType.info, "Removing " ~ to!string(diff) ~ " generators.");
			foreach(int i; 0 .. diff) {
				generators.front.terminate = true;
				generators.removeFront;
			}
		}
		else if(tc > threadCount_) {
			int diff = tc - threadCount_;
			debug writeLog(LogType.info, "Adding " ~ to!string(diff) ~ " generators.");
			foreach(int i; 0 .. diff) {
				createGenerator;
			}
		}

		next = 0;
	}

	private void createGenerator() {
		NoiseGenerator g = createNG();
		g.setFields(resources, this);
		generators.insertBack(g);
	}

	private int next;

	void generate(Chunk c) {
		c.noiseBlocking = true;
		c.needsNoise = false;

		generators[next].add(c);
		next++;

		if(next >= threadCount)
			next = 0;
	}
}

abstract class NoiseGenerator {
	private shared(bool) terminate_;
	@property bool terminate() { return atomicLoad(terminate_); }
	@property void terminate(bool n) { atomicStore(terminate_, n); }

	private shared(bool) busy_;
	@property bool busy() { return atomicLoad(busy_); }
	@property void busy(bool n) { atomicStore(busy_, n); }

	Resources resources;
	NoiseGeneratorManager manager;

	abstract void add(Chunk chunk);

	void setFields(Resources resources, NoiseGeneratorManager manager) {
		this.resources = resources;
		this.manager = manager;
	}

	void setChunkComplete(Chunk c) {
		c.noiseCompleted = true;
		c.noiseBlocking = false;
	}
}

final class DefaultNoiseGenerator : NoiseGenerator {
	private Thread thread;

	private struct Meshes {
		ushort invisible,
			cube,
			slope,
			tetrahedron,
			antiTetrahedron,
			horizontalSlope,
			antiObliquePyramid;

		static Meshes getMeshes(Resources resources) {
			Meshes meshes;
			meshes.invisible = resources.getMesh("block_mesh_invisible").id;
			meshes.cube = resources.getMesh("block_mesh_cube").id;
			meshes.slope = resources.getMesh("block_mesh_slope").id;
			meshes.tetrahedron = resources.getMesh("block_mesh_tetrahedron").id;
			meshes.antiTetrahedron = resources.getMesh("block_mesh_antitetrahedron").id;
			meshes.horizontalSlope = resources.getMesh("block_mesh_horizontal_slope").id;
			return meshes;
		}
	}
	private Meshes meshes;

	private Mutex mutex;
	private Condition condition;
	private Object queueSync = new Object;
	private CyclicBuffer!Chunk chunkQueue;

	this() {
		thread = new Thread(&generator);
		thread.isDaemon = true;

		mutex = new Mutex;
		condition = new Condition(mutex);
	}

	override void add(Chunk chunk) {
		synchronized(queueSync) {
			busy = true;
			chunkQueue.insertBack(chunk);
			synchronized(mutex)
				condition.notify;
		}
	}

	private Chunk getNextFromQueue() {
		bool queueEmpty = false;
		synchronized(queueSync)
			queueEmpty = chunkQueue.empty;

		if(queueEmpty)
			synchronized(mutex)
				condition.wait;

		synchronized(queueSync) {
			Chunk c = chunkQueue.front;
			chunkQueue.removeFront;
			return c;
		}
	}

	override void setFields(Resources resources,NoiseGeneratorManager manager) {
		super.setFields(resources,manager);
		meshes = Meshes.getMeshes(resources);
		thread.start();
	}

	private void generator() {
		OpenSimplexNoise!float osn = new OpenSimplexNoise!(float)(097664884);

		enum sbOffset = 2;
		enum sbDimensions = chunkDimensions + sbOffset * 2;

		source = VoxelBuffer(sbDimensions, sbOffset);
		tempBuffer0 = VoxelBuffer(sbDimensions, sbOffset);
		tempBuffer1 = VoxelBuffer(18, 1);

		import std.datetime.stopwatch;
		StopWatch sw = StopWatch(AutoStart.no);

		scope(exit) throw new Error("Why did I die?");

		while(!terminate) {
			Chunk chunk = getNextFromQueue;
			busy = true;

			sw.start;

			chunk.airCount = 0;

			int premCount = 0;

			foreach(int x; -sbOffset .. chunkDimensions + sbOffset) {
				foreach(int z; -sbOffset .. chunkDimensions + sbOffset) {
					vec3f horizPos = ChunkPosition.blockPosRealCoord(chunk.position, vec3i(x, 0, z));

					/*float height = osn.eval(horizPos.x / 256f, horizPos.z / 256f) * 128f;
					height += osn.eval(horizPos.x / 128f, horizPos.z / 128f) * 64f;
					height += osn.eval(horizPos.x / 64f, horizPos.z / 64f) * 32f;
					height += osn.eval(horizPos.x / 4f, horizPos.z / 4f) * 2f;
					height += osn.eval(horizPos.x, horizPos.z) * 0.25f;*/

					//float height = osn.eval(horizPos.x / 16f, horizPos.z / 16f) * 16f;
					//height += osn.eval(horizPos.x / 64f, horizPos.z / 64f) * 16f;
					//height += osn.eval(horizPos.x / 32f, horizPos.z / 32f) * 2f;
					//height += osn.eval(horizPos.x / 4f, horizPos.z / 4f) * 1f;
					//height += osn.eval(horizPos.x, horizPos.z) * 0.25f;

					float height = 0;

					float mat = osn.eval(horizPos.x / 5.6f + 3275, horizPos.z / 5.6f - 734);

					foreach(int y; -sbOffset .. chunkDimensions + sbOffset) {
						vec3f blockPos = ChunkPosition.blockPosRealCoord(chunk.position, vec3i(x, y, z));

						 //bnif(height > 0)
						//	height = 10;
						//else
						//	height = -10;

						if(blockPos.y <= height) {
							if(mat < 0)
								source.set(x, y, z, Voxel(1, 1, 0, 0));
							else
								source.set(x, y, z, Voxel(2, 1, 0, 0));
						}
						else {
							source.set(x, y, z, Voxel(0, 0, 0, 0));
							premCount++;
						}
					}
				}
			}

			if(premCount < sbDimensions ^^ 3) {
				processNonAntiTetrahedrons(source, tempBuffer0);
				processAntiTetrahedrons(tempBuffer0, tempBuffer1);

				foreach(int x; -voxelOffset .. chunkDimensions + voxelOffset) {
					foreach(int y; -voxelOffset .. chunkDimensions + voxelOffset) {
						foreach(int z; -voxelOffset .. chunkDimensions + voxelOffset) {
							Voxel voxel = tempBuffer1.get(x, y, z);
							chunk.set(x, y, z, voxel);
							if(voxel.mesh == 0) chunk.airCount++;
						}
					}
				}
			}
			else {
				foreach(int x; -voxelOffset .. chunkDimensions + voxelOffset) {
					foreach(int y; -voxelOffset .. chunkDimensions + voxelOffset) {
						foreach(int z; -voxelOffset .. chunkDimensions + voxelOffset) {
							Voxel voxel = source.get(x, y, z);
							chunk.set(x, y, z, voxel);
							if(voxel.mesh == 0) chunk.airCount++;
						}
					}
				}
			}

			setChunkComplete(chunk);

			sw.stop;
			double nt = sw.peek.total!"nsecs"() / 1_000_000.0;
			if(nt < manager.lowestTime || manager.lowestTime == 0) {
				manager.lowestTime = nt;
			}
			if(nt > manager.highestTime || manager.highestTime == 0)
				manager.highestTime = nt;
			if(manager.averageTime == 0)
				manager.averageTime = nt;
			else {
				manager.averageTime += nt;
				manager.averageTime *= 0.5;
			}
			sw.reset;

			busy = false;
		}
	}

	private struct VoxelBuffer {
		Voxel[] voxels;
		
		int dimensions, offset;
		
		this(int dimensions, int offset) {
			this.dimensions = dimensions;
			this.offset = offset;
			voxels = new Voxel[dimensions ^^ 3];
		}
		
		void dupFrom(ref VoxelBuffer other) {
			assert(dimensions == other.dimensions);
			assert(offset == other.offset);
			foreach(int i; 0 .. dimensions ^^ 3)
				voxels[i] = other.voxels[i].dup;
		}
		
		private int flattenIndex(int x, int y, int z) {
			return x + dimensions * (y + dimensions * z);
		}
		
		private void throwIfOutOfBounds(int x, int y, int z) {
			if(x < -offset || y < -offset || z < -offset || x >= dimensions + offset || y >= dimensions + offset || z >= dimensions + offset)
				throw new Exception("Out of bounds.");
		}
		
		Voxel get(int x, int y, int z) {
			debug throwIfOutOfBounds(x, y, z);
			return voxels[flattenIndex(x + offset, y + offset, z + offset)];
		}
		
		void set(int x, int y, int z, Voxel voxel) {
			debug throwIfOutOfBounds(x, y, z);
			voxels[flattenIndex(x + offset, y + offset, z + offset)] = voxel;
		}
	}
	
	private VoxelBuffer source;
	private VoxelBuffer tempBuffer0;
	private VoxelBuffer tempBuffer1;
	
	void processNonAntiTetrahedrons(ref VoxelBuffer source, ref VoxelBuffer tempBuffer0) {
		tempBuffer0.dupFrom(source);
		
		foreach(int x; -voxelOffset .. chunkDimensions + voxelOffset) {
			foreach(int y; -voxelOffset .. chunkDimensions + voxelOffset) {
				foreach(int z; -voxelOffset .. chunkDimensions + voxelOffset) {
					Voxel voxel = source.get(x, y, z);
					
					if(voxel.mesh == 0) {
						//tempBuffer0.set(x, y, z, voxel);
						continue;
					}
					
					Voxel nx = source.get(x - 1, y, z);
					Voxel px = source.get(x + 1, y, z);
					Voxel ny = source.get(x, y - 1, z);
					Voxel py = source.get(x, y + 1, z);
					Voxel nz = source.get(x, y, z - 1);
					Voxel pz = source.get(x, y, z + 1);
					
					Voxel nxnz = source.get(x - 1, y, z - 1);
					Voxel nxpz = source.get(x - 1, y, z + 1);
					Voxel pxnz = source.get(x + 1, y, z - 1);
					Voxel pxpz = source.get(x + 1, y, z + 1);
					
					Voxel pynz = source.get(x, y + 1, z - 1);
					Voxel pypz = source.get(x, y + 1, z + 1);
					Voxel nxpy = source.get(x - 1, y + 1, z);
					Voxel pxpy = source.get(x + 1, y + 1, z);
					
					bool setDef = false;
					
					if(ny.mesh == 0) {
						setDef = true;
					}
					else {
						if(nx.mesh != 0 && px.mesh == 0 && nz.mesh != 0 && pz.mesh != 0 && py.mesh == 0) 
							tempBuffer0.set(x, y, z, Voxel(voxel.material, 2, voxel.materialData, 0));
						else if(px.mesh != 0 && nx.mesh == 0 && nz.mesh != 0 && pz.mesh != 0 && py.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.slope, voxel.materialData, 2));
						else if(nz.mesh != 0 && pz.mesh == 0 && nx.mesh != 0 && px.mesh != 0 && py.mesh == 0) 
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.slope, voxel.materialData, 1));
						else if(pz.mesh != 0 && nz.mesh == 0 && nx.mesh != 0 && px.mesh != 0 && py.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.slope, voxel.materialData, 3));
						
						else if(nx.mesh != 0 && nz.mesh != 0 && px.mesh == 0 && pz.mesh == 0 && py.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.tetrahedron, voxel.materialData, 0));
						
						else if(px.mesh != 0 && nz.mesh != 0 && nx.mesh == 0 && pz.mesh == 0 && py.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.tetrahedron, voxel.materialData, 1));
						
						else if(px.mesh != 0 && pz.mesh != 0 && nx.mesh == 0 && nz.mesh == 0 && py.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.tetrahedron, voxel.materialData, 2));
						
						else if(nx.mesh != 0 && pz.mesh != 0 && px.mesh == 0 && nz.mesh == 0 && py.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.tetrahedron, voxel.materialData, 3));
						
						else if(nx.mesh != 0 && pz.mesh != 0 && px.mesh == 0 && nz.mesh == 0 && pxnz.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.horizontalSlope, voxel.materialData, 0));
						else if(nx.mesh != 0 && nz.mesh != 0 && px.mesh == 0 && pz.mesh == 0 && pxpz.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.horizontalSlope, voxel.materialData, 1));
						else if(px.mesh != 0 && nz.mesh != 0 && nx.mesh == 0 && pz.mesh == 0 && nxpz.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.horizontalSlope, voxel.materialData, 2));
						else if(px.mesh != 0 && pz.mesh != 0 && nx.mesh == 0 && nz.mesh == 0 && nxnz.mesh == 0)
							tempBuffer0.set(x, y, z, Voxel(voxel.material, meshes.horizontalSlope, voxel.materialData, 3));
						
						else setDef = true;
					}
					
					if(setDef)
						tempBuffer0.set(x, y, z, voxel);
				}
			}
		}
	}
	
	void processAntiTetrahedrons(ref VoxelBuffer tempBuffer0, ref VoxelBuffer tempBuffer1) {
		foreach(int x; -voxelOffset .. chunkDimensions + voxelOffset) {
			foreach(int y; -voxelOffset .. chunkDimensions + voxelOffset) {
				foreach(int z; -voxelOffset .. chunkDimensions + voxelOffset) {
					Voxel voxel = tempBuffer0.get(x, y, z);
					
					if(voxel.mesh == 0) {
						tempBuffer1.set(x, y, z, voxel);
						continue;
					}
					
					bool setDef = false;
					
					Voxel nx = tempBuffer0.get(x - 1, y, z);
					Voxel px = tempBuffer0.get(x + 1, y, z);
					Voxel ny = tempBuffer0.get(x, y - 1, z);
					Voxel py = tempBuffer0.get(x, y + 1, z);
					Voxel nz = tempBuffer0.get(x, y, z - 1);
					Voxel pz = tempBuffer0.get(x, y, z + 1);
					
					Voxel nxnz = tempBuffer0.get(x - 1, y, z - 1);
					Voxel nxpz = tempBuffer0.get(x - 1, y, z + 1);
					Voxel pxnz = tempBuffer0.get(x + 1, y, z - 1);
					Voxel pxpz = tempBuffer0.get(x + 1, y, z + 1);
					
					if(ny.mesh == 0) {
						setDef = true;
					}
					else {
						if(nx.mesh != 0 && nz.mesh != 0 && px.mesh != 0 && pz.mesh != 0) {
							if(pxpz.mesh == 0 && !(px.mesh == meshes.cube || pz.mesh == meshes.cube))
								tempBuffer1.set(x, y, z, Voxel(voxel.material, 4, voxel.materialData, 0));
							else if(nxpz.mesh == 0 && !(nx.mesh == meshes.cube || pz.mesh == meshes.cube))
								tempBuffer1.set(x, y, z, Voxel(voxel.material, 4, voxel.materialData, 1));
							else if(nxnz.mesh == 0 && !(nx.mesh == meshes.cube || nz.mesh == meshes.cube))
								tempBuffer1.set(x, y, z, Voxel(voxel.material, 4, voxel.materialData, 2));
							else if(pxnz.mesh == 0 && !(px.mesh == meshes.cube || nz.mesh == meshes.cube))
								tempBuffer1.set(x, y, z, Voxel(voxel.material, 4, voxel.materialData, 3));
							else setDef = true;
						}
						else if(voxel.mesh == meshes.cube && nx.mesh == meshes.cube && px.mesh != meshes.cube && nz.mesh == 0 && pz.mesh == meshes.cube && py.mesh != meshes.cube)
							tempBuffer1.set(x, y, z, Voxel(voxel.material, 4, voxel.materialData, 3));
						else if(voxel.mesh == meshes.cube && nx.mesh == meshes.cube && px.mesh == 0 && nz.mesh != meshes.cube && pz.mesh == meshes.cube && py.mesh != meshes.cube)
							tempBuffer1.set(x, y, z, Voxel(voxel.material, 4, voxel.materialData, 3));
						else if(voxel.mesh == meshes.cube && nx.mesh == meshes.cube && px.mesh == 0 && nz.mesh == meshes.cube && pz.mesh != meshes.cube && py.mesh != meshes.cube)
							tempBuffer1.set(x, y, z, Voxel(voxel.material, 4, voxel.materialData, 0));
						else if(voxel.mesh == meshes.cube && nx.mesh == meshes.cube && px.mesh != meshes.cube && nz.mesh == meshes.cube && pz.mesh == 0 && py.mesh != meshes.cube)
							tempBuffer1.set(x, y, z, Voxel(voxel.material, 4, voxel.materialData, 0));
						else if(voxel.mesh == meshes.cube && nx.mesh == 0 && px.mesh == meshes.cube && nz.mesh != meshes.cube && pz.mesh == meshes.cube && py.mesh != meshes.cube)
							tempBuffer1.set(x, y, z, Voxel(voxel.material, 4, voxel.materialData, 2));
						else if(voxel.mesh == meshes.cube && nx.mesh != meshes.cube && px.mesh == meshes.cube && nz.mesh == 0 && pz.mesh == meshes.cube && py.mesh != meshes.cube)
							tempBuffer1.set(x, y, z, Voxel(voxel.material, 4, voxel.materialData, 2));
						else if(voxel.mesh == meshes.cube && nx.mesh == 0 && px.mesh == meshes.cube && nz.mesh == meshes.cube && pz.mesh != meshes.cube && py.mesh != meshes.cube)
							tempBuffer1.set(x, y, z, Voxel(voxel.material, 4, voxel.materialData, 1));
						else if(voxel.mesh == meshes.cube && nx.mesh != meshes.cube && px.mesh == meshes.cube && nz.mesh == meshes.cube && pz.mesh == 0 && py.mesh != meshes.cube)
							tempBuffer1.set(x, y, z, Voxel(voxel.material, 4, voxel.materialData, 1));
						else setDef = true;
					}
					
					if(setDef)
						tempBuffer1.set(x, y, z, voxel);
				}
			}
		}
	}
}