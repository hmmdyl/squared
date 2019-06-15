module squareone.terrain.basic.manager;

import squareone.terrain.basic.chunk;
import squareone.terrain.gen.noisegen;
import squareone.voxel;
import moxane.core;
import moxane.graphics.renderer;

import dlib.math;
import std.datetime.stopwatch;
import std.parallelism;
import std.typecons;

final class BasicTerrainRenderer : IRenderable
{
	BasicTerrainManager btm;
	invariant { assert(btm !is null); }

	this(BasicTerrainManager btm)
	{ this.btm = btm; }

	void render(Renderer renderer, ref LocalContext lc, out uint drawCalls, out uint numVerts)
	{
		foreach(proc; 0 .. btm.resources.processorCount)
		{
			IProcessor p = btm.resources.getProcessor(proc);
			p.prepareRender(renderer);
			scope(exit) p.endRender;

			foreach(ref BasicChunk chunk; btm.chunksTerrain)
				p.render(chunk.chunk, lc, drawCalls, numVerts);
		}
	}
}

struct BasicTMSettings
{
	Vector3i addRange, extendedAddRange, removeRange;
	Resources resources;
}

final class BasicTerrainManager
{
	enum ChunkState
	{
		notLoaded,
		hibernated,
		active
	}

	Resources resources;
	Moxane moxane;

	private BasicChunk[ChunkPosition] chunksTerrain;
	private ChunkState[ChunkPosition] chunkStates;

	const BasicTMSettings settings;

	Vector3f cameraPosition;
	NoiseGeneratorManager noiseGeneratorManager;

	this(Moxane moxane, BasicTMSettings settings)
	{
		this.moxane = moxane;
		this.settings = settings;
		resources = settings.resources;

		voxel = VoxelInteraction(this);

		noiseGeneratorManager = new NoiseGeneratorManager(resources, 1, () => new DefaultNoiseGenerator(moxane), 0);
		auto ecpcNum = (settings.extendedAddRange.x * 2 + 1) * (settings.extendedAddRange.y * 2 + 1) * (settings.extendedAddRange.z * 2 + 1);
		extensionCPCache = new ChunkPosition[ecpcNum];
	}

	~this()
	{
		destroy(noiseGeneratorManager);
	}

	void update()
	{
		const ChunkPosition cp = ChunkPosition.fromVec3f(cameraPosition);

		addChunksLocal(cp);
		//addChunksExtension(cp);
		foreach(ref BasicChunk bc; chunksTerrain)
		{
			manageChunkState(bc);
			removeChunkHandler(bc, cp);
		}
	}

	private BasicChunk createChunk(ChunkPosition pos, bool needsData = true)
	{
		Chunk c = new Chunk(resources);
		c.initialise;
		c.needsData = needsData;
		c.lod = 0;
		c.blockskip = 1;
		return BasicChunk(c, pos);
	}

	private void addChunksLocal(const ChunkPosition cp)
	{
		Vector3i lower = Vector3i(
			cp.x - settings.addRange.x,
			cp.y - settings.addRange.y,
			cp.z - settings.addRange.z);
		Vector3i upper = Vector3i(
			cp.x + settings.addRange.x,
			cp.y + settings.addRange.y,
			cp.z + settings.addRange.z);

		for(int x = lower.x; x < upper.x; x++)
		{
			for(int y = lower.y; y < upper.y; y++)
			{
				for(int z = lower.z; z < upper.z; z++)
				{
					auto newCp = ChunkPosition(x, y, z);

					ChunkState* getter = newCp in chunkStates;
					bool doAdd = getter is null || *getter == ChunkState.notLoaded;

					if(doAdd)
					{
						auto chunk = createChunk(newCp);
						chunksTerrain[newCp] = chunk;
						chunkStates[newCp] = ChunkState.active;

						//chunksAdded++;
					}
					else
					{

						//pendingRemove = false;
					}
				}
			}
		}
	}

	private void removeChunkHandler(ref BasicChunk chunk, const ChunkPosition camera)
	{
		if(!isChunkInBounds(camera, chunk.position))
		{
			if(chunk.chunk.needsData || chunk.chunk.dataLoadBlocking || chunk.chunk.dataLoadCompleted ||
			   chunk.chunk.needsMesh || chunk.chunk.isAnyMeshBlocking)
				chunk.chunk.pendingRemove = true;
			else
			{
				foreach(int proc; 0 .. resources.processorCount)
					resources.getProcessor(proc).removeChunk(chunk.chunk);

				chunksTerrain.remove(chunk.position);
				chunk.chunk.deinitialise();
			}
		}
	}

	private StopWatch addExtensionSortSw;
	private bool isExtensionCacheSorted;
	private ChunkPosition[] extensionCPCache;

	private void addChunksExtension(const ChunkPosition cam)
	{
		bool doSort;

		if(!addExtensionSortSw.running)
		{
			addExtensionSortSw.start;
			doSort = true;
		}
		if(addExtensionSortSw.peek.total!"msecs"() >= 300)
		{
			addExtensionSortSw.reset;
			addExtensionSortSw.start;
			doSort = true;
		}

		if(doSort)
		{
			isExtensionCacheSorted = false;

			Vector3i lower;
			lower.x = cam.x - settings.extendedAddRange.x;
			lower.y = cam.y - settings.extendedAddRange.y;
			lower.z = cam.z - settings.extendedAddRange.z;
			Vector3i upper;
			upper.x = cam.x + settings.extendedAddRange.x;
			upper.y = cam.y + settings.extendedAddRange.y;
			upper.z = cam.z + settings.extendedAddRange.z;

			int c;
			foreach(int x; lower.x .. upper.x)
				foreach(int y; lower.y .. upper.y)
					foreach(int z; lower.z .. upper.z)
						extensionCPCache[c++] = ChunkPosition(x, y, z);

			float camf = cam.toVec3f.length;

			auto cdCmp(ChunkPosition x, ChunkPosition y)
			{
				float x1 = x.toVec3f.length - camf;
				float y1 = y.toVec3f.length - camf;
				return x1 < y1;
			}

			void sortTask(ChunkPosition[] cache)
			{
				import std.algorithm.sorting : sort;
				sort!cdCmp(cache);
				isExtensionCacheSorted = true;
			}

			taskPool.put(task(&sortTask, extensionCPCache));
		}

		if(!isExtensionCacheSorted) return;

		int doAddNum;
		enum addMax = 4;

		foreach(ChunkPosition pos; extensionCPCache)
		{
			ChunkState* getter = pos in chunkStates;
			bool doAdd = getter is null || *getter == ChunkState.notLoaded;

			if(doAdd)
			{
				if(doAddNum > addMax) return;

				BasicChunk chunk = createChunk(pos);
				chunksTerrain[pos] = chunk;
				chunkStates[pos] = ChunkState.active;

				doAddNum++;
			}
		}
	}

	private void manageChunkState(ref BasicChunk bc)
	{
		with(bc)
		{
			if(chunk.needsData && !chunk.isAnyMeshBlocking) 
			{
				auto ngo = NoiseGeneratorOrder(chunk, position.toVec3d);
				ngo.loadChunk = true;
				ngo.setLoadAll();
				noiseGeneratorManager.generate(ngo);
			}
			if(chunk.dataLoadCompleted)
			{
				chunk.needsMesh = true;
				chunk.dataLoadCompleted = false;
			}

			if(chunk.needsMesh && !chunk.needsData && !chunk.dataLoadBlocking && !chunk.dataLoadCompleted)
			{
				if(chunk.airCount == ChunkData.chunkOverrunDimensionsCubed || 
				   chunk.solidCount == ChunkData.chunkOverrunDimensionsCubed) 
				{
					chunksTerrain.remove(position);
					chunk.deinitialise();
					chunkStates[position] = ChunkState.hibernated;
					//chunksHibernated++;
					return;
				}
				else
				{
					foreach(int proc; 0 .. resources.processorCount)
						resources.getProcessor(proc).meshChunk(MeshOrder(chunk, true, true, false));
				}
				chunk.needsMesh = false;
			}
		}
	}

	private bool isChunkInBounds(ChunkPosition camera, ChunkPosition position)
	{
		return position.x >= camera.x - settings.removeRange.x && position.x < camera.x + settings.removeRange.x &&
			position.y >= camera.y - settings.removeRange.y && position.y < camera.y + settings.removeRange.y &&
			position.z >= camera.z - settings.removeRange.z && position.z < camera.z + settings.removeRange.z;
	}

	struct VoxelInteraction
	{
		private BasicTerrainManager manager;
		invariant { assert(manager !is null); }
		
		Nullable!Voxel get(long x, long y, long z)
		{
			ChunkPosition cp;
			BlockOffset offset;
			ChunkPosition.blockPosToChunkPositionAndOffset(Vector!(long, 3)(x, y, z), cp, offset);
			return get(cp, offset);
		}

		Nullable!Voxel get(ChunkPosition chunkPosition, BlockOffset cp)
		{
			ChunkState* state = chunkPosition in manager.chunkStates;
			if(state is null || *state != ChunkState.active)
			{
				Nullable!Voxel ret;
				ret.nullify;
				return ret;
			}

			return Nullable!Voxel(manager.chunksTerrain[chunkPosition].chunk.get(cp.x, cp.y, cp.z));
		}

	}
	VoxelInteraction voxel;
}

class TerrainDataStream
{
	
}