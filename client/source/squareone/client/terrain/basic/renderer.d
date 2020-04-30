module squareone.client.terrain.basic.renderer;

import squareone.client.terrain.basic.engine;
import squareone.client.terrain.basic.chunk;
import squareone.client.voxel;
import squareone.common.voxel : ChunkData;

import moxane.core;
import moxane.graphics.redo;

import dlib.math;
import dlib.geometry : Frustum, Sphere;
import std.math;
import std.datetime.stopwatch;

@safe:

final class TerrainRenderer : IDrawable
{
	bool culling;

	TerrainEngine engine;
	this(TerrainEngine engine) in(engine !is null) { this.engine = engine; }

	void draw(Pipeline pipeline, ref LocalContext context, ref PipelineStatics stats) @trusted 
	{
		Matrix4f viewProjection = context.camera.projection * context.camera.viewMatrix;
		Frustum frustum = Frustum(viewProjection);

		immutable Vector3i min = engine.camera.asChunk.toVec3i - engine.settings.removeRange;
		immutable Vector3i max = engine.camera.asChunk.toVec3i + (engine.settings.removeRange + 1);

		foreach(proc; 0 .. engine.resources.processorCount)
		{
			IClientProcessor p = cast(IClientProcessor)engine.resources.getProcessor(proc);
			p.beginDraw(pipeline, context);
			scope(exit) p.endDraw(pipeline, context);

			if(!culling)
			{
				foreach(Chunk chunk; engine.chunks)
					p.drawChunk(chunk, context, stats);
			}
			else
			{
				bool shouldRender(Chunk chunk)
				{
					immutable Vector3f chunkPosReal = chunk.position.toVec3f;
					immutable float dimReal = ChunkData.chunkDimensionsMetres * chunk.blockskip;
					immutable Vector3f center = Vector3f(chunkPosReal.x + dimReal * 0.5f, chunkPosReal.y + dimReal * 0.5f, chunkPosReal.z + dimReal * 0.5f);
					immutable float radius = sqrt(dimReal ^^ 2 + dimReal ^^ 2);
					Sphere s = Sphere(center, radius);

					return frustum.intersectsSphere(s);
				}

				foreach(Chunk chunk; engine.chunks)
				{
					if(!shouldRender(chunk)) continue;
					p.drawChunk(chunk, context, stats);
				}
			}
		}
	}
}