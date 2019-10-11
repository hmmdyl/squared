module squareone.voxelcontent.glass.processor;

import squareone.voxelcontent.glass.types;
import squareone.voxelcontent.glass.mesher;
import squareone.voxelcontent.block.processor;
import squareone.voxel;
import squareone.util.spec;

import moxane.core;
import moxane.graphics.renderer;
import moxane.graphics.effect;
import moxane.graphics.log;
import moxane.utils.pool;
import moxane.utils.maybe;

import derelict.opengl3.gl3;
import dlib.math;

import std.file : readText;

final class GlassProcessor : IProcessor
{
	GlassMesh glassMesh;

	BlockProcessor blockProcessor;
	Resources resources;
	Moxane moxane;

	Renderer renderer;

	private Pool!(RenderData*) renderDataPool;
	package Pool!(CompressedMeshBuffer) meshBufferPool;
	package Channel!MeshResult meshResults;

	private enum mesherCount = 1;
	private size_t meshBarrel;
	private GlassMesher[] meshers;

	private GLuint vertexArrayObject;
	private Effect effect;

	this(Moxane moxane, BlockProcessor bp)
	in(moxane !is null) in(bp !is null)
	do {
		this.moxane = moxane;
		this.blockProcessor = bp;

		meshResults = new Channel!MeshResult;

		meshBufferPool = Pool!(CompressedMeshBuffer)(() => new CompressedMeshBuffer, 2, false);
		renderDataPool = Pool!(RenderData*)(() => new RenderData(), 8);
	}

	~this() 
	{
		glDeleteVertexArrays(1, &vertexArrayObject);
		foreach(x; 0 .. meshers.length)
			destroy(meshers[x]);
		meshers[] = null;
	}

	void finaliseResources(Resources res)
	{
		Log log = moxane.services.getAOrB!(VoxelLog, Log);
		Log graphicsLog = moxane.services.getAOrB!(GraphicsLog, Log);

		if(res is null)
		{
			enum errorStr = "Resources cannot be null";
			log.write(Log.Severity.error, errorStr);
			throw new Exception(errorStr);
		}
		resources = res;

		meshers = new GlassMesher[](mesherCount);
		foreach(x; 0 .. mesherCount)
			meshers[x] = new GlassMesher(this, &meshBufferPool, meshResults);

		glassMesh = cast(GlassMesh)res.getMesh(GlassMesh.technicalStatic);
		if(res is null)
		{
			enum errorStr = GlassMesh.stringof ~ " " ~ GlassMesh.technicalStatic ~ " must be present.";
			log.write(Log.Severity.error, errorStr);
			throw new Exception(errorStr);
		}
		glassMesh.bp = blockProcessor;

		glGenVertexArrays(1, &vertexArrayObject);

		Shader vs = new Shader;
		vs.compile(readText(AssetManager.translateToAbsoluteDir("content/shaders/glassProcessor.vs.glsl")), GL_VERTEX_SHADER, graphicsLog);
		Shader fs = new Shader;
		fs.compile(readText(AssetManager.translateToAbsoluteDir("content/shaders/glassProcessor.fs.glsl")), GL_FRAGMENT_SHADER, graphicsLog);

		effect = new Effect(moxane, GlassProcessor.stringof);
		effect.attachAndLink(vs, fs);
		effect.bind;
		effect.findUniform("ModelViewProjection");
		effect.findUniform("ModelView");
		effect.findUniform("Model");
		effect.findUniform("Fit10bScale");
		effect.findUniform("SceneDiffuse");
		effect.unbind;
	}

	void meshChunk(MeshOrder mo) 
	{
		mo.chunk.meshBlocking(true, id_);
		meshers[meshBarrel].orders.send(mo);
		meshBarrel++;
		if(meshBarrel >= mesherCount) meshBarrel = 0;
	}

	void removeChunk(IMeshableVoxelBuffer vb) 
	{
		if(isRdNull(vb)) return;

		RenderData* rd = getRd(vb);
		rd.destroy;
		renderDataPool.give(rd);

		vb.renderData[id_] = null;
	}

	void updateFromManager() {}

	void performUploads()
	{
		while(!meshResults.empty)
		{
			Maybe!MeshResult meshResultM = meshResults.tryGet;
			if(meshResultM.isNull) return;

			MeshResult meshResult = *meshResultM.unwrap;

			if(meshResult.buffer is null)
			{
				if(!isRdNull(meshResult.order.chunk))
					removeChunk(meshResult.order.chunk);
				continue;
			}

			bool hasRD = !isRdNull(meshResult.order.chunk);
			RenderData *rd;
			if(hasRD)
				rd = getRd(meshResult.order.chunk);
			else
			{
				rd = renderDataPool.get;
				rd.create;
				meshResult.order.chunk.renderData[id_] = cast(void*)rd;
			}

			rd.vertexCount = meshResult.buffer.vertexCount;
			rd.chunkMax = meshResult.buffer.chunkMax;
			rd.fit10BitScale = meshResult.buffer.fit10Bit;

			glBindBuffer(GL_ARRAY_BUFFER, rd.vertexBO);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, meshResult.buffer.vertices.ptr, GL_STATIC_DRAW);

			glBindBuffer(GL_ARRAY_BUFFER, rd.normalBO);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, meshResult.buffer.normals.ptr, GL_STATIC_DRAW);

			glBindBuffer(GL_ARRAY_BUFFER, rd.metaBO);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * ubyte.sizeof * 4, meshResult.buffer.colours.ptr, GL_STATIC_DRAW);

			glBindBuffer(GL_ARRAY_BUFFER, 0);

			meshResult.order.chunk.meshBlocking(false, id_);
			meshResult.buffer.reset;
			meshBufferPool.give(meshResult.buffer);
		}
	}

	void prepareRender(Renderer renderer) 
	{
		this.renderer = renderer;

		performUploads;

		glBindVertexArray(vertexArrayObject);
		foreach(x; 0 .. channels) glEnableVertexAttribArray(x);

		effect.bind;
		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, renderer.postProcesses.lightTexture.diffuse);
		effect["SceneDiffuse"].set(0);
	}

	void render(IMeshableVoxelBuffer vb, ref LocalContext lc, ref uint dc, ref uint nv)
	{
		if(lc.type != PassType.glass) return;
		if(isRdNull(vb)) return;

		RenderData* rd = getRd(vb);
		Matrix4f m = translationMatrix(vb.transform.position);
		Matrix4f nm = lc.model * m;
		Matrix4f mv = lc.view * nm;
		Matrix4f mvp = lc.projection * mv;

		effect["ModelViewProjection"].set(&mvp);
		effect["ModelView"].set(&mv);
		effect["Model"].set(&nm);
		effect["Fit10bScale"].set(rd.fit10BitScale);

		glBindBuffer(GL_ARRAY_BUFFER, rd.vertexBO);
		glVertexAttribPointer(0, 4, GL_UNSIGNED_INT_2_10_10_10_REV, false, 0, null);

		glBindBuffer(GL_ARRAY_BUFFER, rd.normalBO);
		glVertexAttribPointer(1, 4, GL_UNSIGNED_INT_2_10_10_10_REV, false, 0, null);

		glBindBuffer(GL_ARRAY_BUFFER, rd.metaBO);
		glVertexAttribIPointer(2, 4, GL_UNSIGNED_BYTE, 0, null);

		glDrawArrays(GL_TRIANGLES, 0, rd.vertexCount);

		nv += rd.vertexCount;
		dc++;
	}

	void endRender() 
	{
		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, 0);

		foreach(x; 0 .. channels) glDisableVertexAttribArray(x);

		effect.unbind;

		glBindVertexArray(0);
	}

	package ubyte id_;
	@property ubyte id() { return id_; }
	@property void id(ubyte n) { id_ = n; }

	mixin(VoxelContentQuick!("squareOne:voxel:processor:glass", "", appName, dylanGrahamName));

	pragma(inline, true)
		private bool isRdNull(IMeshableVoxelBuffer vb) { return vb.renderData[id_] is null; }
	pragma(inline, true)
		private RenderData* getRd(IMeshableVoxelBuffer vb) { return cast(RenderData*)vb.renderData[id_]; }

	IMesher requestMesher(IChannel!MeshOrder source) {return null;}
	void returnMesher(IMesher m) {}
}