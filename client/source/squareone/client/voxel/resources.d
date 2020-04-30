module squareone.client.voxel.resources;

import moxane.core;
import moxane.graphics.redo;

import squareone.common.voxel;

@safe:

interface IClientProcessor : IProcessor
{
	void beginDraw(Pipeline pipeline, ref LocalContext context);
	void drawChunk(IMeshableVoxelBuffer chunk, ref LocalContext context, ref PipelineStatics stats);
	void endDraw(Pipeline pipeline, ref LocalContext context);
}