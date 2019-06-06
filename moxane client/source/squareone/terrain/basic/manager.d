module squareone.terrain.basic.manager;

import squareone.terrain.basic.chunk;

import squareone.voxel;
import moxane.core;
import moxane.graphics.renderer;

import dlib.math;

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

final class BasicTerrainManager
{
	Resources resources;

	private BasicChunk[ChunkPosition] chunksTerrain;
}