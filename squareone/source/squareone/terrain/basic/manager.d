module squareone.terrain.basic.manager;

import squareone.terrain.basic.chunk;
import squareone.terrain.gen.noisegen;

import squareone.voxel;
import moxane.core;
import moxane.graphics.renderer;

import dlib.math;
import std.datetime.stopwatch;
import std.parallelism;

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

	private BasicChunk[ChunkPosition] chunksTerrain;
	private ChunkState[ChunkPosition] chunkHoles;

	const BasicTMSettings settings;

	Vector3f cameraPosition;
	NoiseGeneratorManager noiseGeneratorManager;

	this(BasicTMSettings settings)
	{
		this.settings = settings;
		resources = settings.resources;

		noiseGeneratorManager = new NoiseGeneratorManager(resources, 1, () => new DefaultNoiseGenerator(), 0);
	}

	void update()
	{
		const ChunkPosition cp = ChunkPosition.fromVec3f(cameraPosition);

		addChunksLocal(cp);
		foreach(ref BasicChunk bc; chunksTerrain)
		{
			manageChunkState(bc);
		}
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

					BasicChunk* getter = newCp in chunksTerrain;
					bool doAdd = getter is null;// || *getter == ChunkState.notLoaded;

					if(doAdd)
					{
						auto c = new Chunk(resources);
						c.initialise();
						c.needsData = true;
						c.lod = 0;
						c.blockskip = 1;
						auto chunk = BasicChunk(c, newCp);
						chunksTerrain[newCp] = chunk;
						chunkHoles[newCp] = ChunkState.active;

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

			Vector3f camf = cam.toVec3f.length;

			auto cdCmp(ChunkPosition x, ChunkPosition y)
			{

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
					chunkHoles[position] = ChunkState.hibernated;
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
}