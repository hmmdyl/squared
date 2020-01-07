module squareone.voxelcontent.block.processor;

import squareone.voxel;
import squareone.util.spec;
import squareone.voxelcontent.block.types;
import squareone.voxelcontent.block.mesher;
import moxane.core;
import moxane.graphics.effect;
import moxane.graphics.renderer;
import moxane.graphics.texture : Texture2DArray, Filter;
import moxane.graphics.log;
import moxane.utils.pool;

import moxane.physics;

import dlib.math;

import std.container.dlist;
import std.datetime.stopwatch;
import std.parallelism;

final class BlockProcessor : IProcessor
{
	private ubyte id_;
	@property ubyte id() { return id_; }
	@property void id(ubyte n) { id_ = n; }

	mixin(VoxelContentQuick!("squareOne:voxel:processor:block", "", appName, dylanGrahamName));

	private Pool!(RenderData*) renderDataPool;
	private MeshBufferHost meshBufferHost;
	package DList!MeshResult uploadQueue;
	package Object uploadSyncObj;

	Resources resources;
	Moxane moxane;

	private uint vao;
	private Effect effect;

	private IBlockVoxelMesh[int] blockMeshes;
	IBlockVoxelTexture[] textures;
	private Texture2DArray textureArray;

	this(Moxane moxane, IBlockVoxelTexture[] textures)
	{
		this.moxane = moxane;
		this.textures = textures;

		foreach(id, IBlockVoxelTexture t; this.textures) t.id = cast(ushort)id;

		meshBufferHost = new MeshBufferHost;
		uploadSyncObj = new Object;
		renderDataPool = Pool!(RenderData*)(() => new RenderData(), 64);
	}

	void finaliseResources(Resources res)
	{
		this.resources = res;

		foreach(int x; 0 .. res.meshCount) 
		{
			IBlockVoxelMesh bm = cast(IBlockVoxelMesh)res.getMesh(x);
			if(bm is null)
				continue;

			blockMeshes[x] = bm;
		}

		foreach(IBlockVoxelMesh bm; blockMeshes.values)
			bm.finalise(this);

		blockMeshes.rehash();

		string[] textureFiles = new string[](textures.length);
		foreach(size_t x, IBlockVoxelTexture texture; textures)
			textureFiles[x] = texture.file;

		textureArray = new Texture2DArray(textureFiles, true, Filter.nearest, Filter.nearest, true);

		foreach(int x; 0 .. res.materialCount) 
		{
			IBlockVoxelMaterial bm = cast(IBlockVoxelMaterial)res.getMaterial(x);
			if(bm is null) 
				continue;

			bm.loadTextures(this);
		}

		import std.file : readText;
		import derelict.opengl3.gl3 : GL_VERTEX_SHADER, GL_FRAGMENT_SHADER, glGenVertexArrays;

		glGenVertexArrays(1, &vao);

		Log log = moxane.services.getAOrB!(GraphicsLog, Log);
		Shader vs = new Shader, fs = new Shader;
		vs.compile(readText(AssetManager.translateToAbsoluteDir("content/shaders/blockProcessor.vs.glsl")), GL_VERTEX_SHADER, log);
		fs.compile(readText(AssetManager.translateToAbsoluteDir("content/shaders/blockProcessor.fs.glsl")), GL_FRAGMENT_SHADER, log);
		effect = new Effect(moxane, BlockProcessor.stringof);
		effect.attachAndLink(vs, fs);
		effect.bind();
		effect.findUniform("ModelViewProjection");
		effect.findUniform("Fit10bScale");
		effect.findUniform("Diffuse");
		effect.findUniform("Model");
		effect.findUniform("ModelView");
		effect.unbind();
	}

	~this()
	{
		import derelict.opengl3.gl3 : glDeleteVertexArrays;
		glDeleteVertexArrays(1, &vao);
	}

	struct MeshResult
	{
		MeshOrder order;
		MeshBuffer buffer;
	}
	EventWaiter!MeshResult onCustomCompletion;

	void removeChunk(IMeshableVoxelBuffer c)
	{
		if(isRdNull(c)) return;
		
		RenderData* rd = getRd(c);
		rd.destroy;
		renderDataPool.give(rd);

		c.renderData[id_] = null;
	}

	private bool isRdNull(IMeshableVoxelBuffer vb) { return vb.renderData[id_] is null; }
	private RenderData* getRd(IMeshableVoxelBuffer vb) { return cast(RenderData*)vb.renderData[id_]; }

	void updateFromManager(){}

	private uint[] compressionBuffer = new uint[](vertsFull);
	private StopWatch uploadItemSw = StopWatch(AutoStart.no);

	private void performUploads() {
		import derelict.opengl3.gl3;

		bool isEmpty() {
			synchronized(uploadSyncObj) {
				return uploadQueue.empty;
			}
		}

		MeshResult getFromUploadQueue() {
			synchronized(uploadSyncObj) {
				if(uploadQueue.empty) throw new Exception("die");
				MeshResult i = uploadQueue.front;
				uploadQueue.removeFront();
				return i;
			}
		}

		uploadItemSw.start();

		/+while(uploadItemSw.peek().total!"msecs" < 4 && !isEmpty())+/{
			if(isEmpty) return;

			MeshResult upItem = getFromUploadQueue();
			IMeshableVoxelBuffer chunk = upItem.order.chunk;

			if(upItem.buffer is null)
			{
				upItem.order.chunk.meshBlocking(false, id_);
				if(!isRdNull(chunk))
				{
					RenderData* rd = getRd(chunk);
					if(rd.collider !is null)
					{
						destroy(rd.collider);
						destroy(rd.rigidBody);
					}
					rd.destroy;
				}
				//continue;
				return;
			}

			bool hasRd = !isRdNull(chunk);
			RenderData* rd;
			if(hasRd) {
				rd = getRd(chunk);
			}
			else {
				rd = renderDataPool.get();
				rd.create();
				chunk.renderData[id_] = cast(void*)rd;
			}

			if(rd.collider !is null)
			{
				rd.collider.destroy;
				rd.rigidBody.destroy;
			}

			void createPhys()
			{
				rd.collider = new StaticMeshCollider(moxane.services.get!PhysicsSystem, upItem.buffer.vertices[0..upItem.buffer.vertexCount], true, false);
				rd.rigidBody = new BodyMT(moxane.services.get!PhysicsSystem, BodyMT.Mode.dynamic, rd.collider, AtomicTransform(upItem.order.chunk.transform));
				rd.rigidBody.collidable = true;
			}
			createPhys;

			rd.vertexCount = upItem.buffer.vertexCount;

			rd.chunkMax = upItem.buffer.chunkMax;
			rd.fit10BitScale = upItem.buffer.fit10Bit;

			glBindBuffer(GL_ARRAY_BUFFER, rd.vertexBO);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, upItem.buffer.compressedVertices.ptr, GL_STATIC_DRAW);
			glBindBuffer(GL_ARRAY_BUFFER, rd.normalBO);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, upItem.buffer.compressedNormals.ptr, GL_STATIC_DRAW);

			glBindBuffer(GL_ARRAY_BUFFER, rd.metaBO);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, upItem.buffer.meta.ptr, GL_STATIC_DRAW);
			glBindBuffer(GL_ARRAY_BUFFER, 0);

			chunk.meshBlocking(false, id_);

			upItem.buffer.reset;
			meshBufferHost.give(upItem.buffer);
		}

		//uploadItemSw.stop();
		//uploadItemSw.reset();
	}

	Renderer currentRenderer;
	void prepareRender(Renderer r)
	{
		import derelict.opengl3.gl3;

		performUploads;
		glBindVertexArray(vao);

		foreach(x; 0 .. 3)
			glEnableVertexAttribArray(x);

		effect.bind;

		this.currentRenderer = r;
		
		glActiveTexture(GL_TEXTURE0);
		textureArray.bind;
		effect["Diffuse"].set(0);
	}

	void render(IMeshableVoxelBuffer chunk, ref LocalContext lc, ref uint drawCalls, ref uint numVerts)
	{
		if(!(lc.type == PassType.shadow || lc.type == PassType.scene)) return;

		RenderData* rd = getRd(chunk);
		if(rd is null) return;

		Matrix4f m = translationMatrix(chunk.transform.position);
		Matrix4f nm = /*lc.model **/ m;
		Matrix4f mvp = lc.projection * lc.view * nm;
		Matrix4f mv = lc.view * nm;

		effect["ModelViewProjection"].set(&mvp);
		effect["Model"].set(&nm);
		effect["ModelView"].set(&mv);

		effect["Fit10bScale"].set(rd.fit10BitScale);

		import derelict.opengl3.gl3;
		glBindBuffer(GL_ARRAY_BUFFER, rd.vertexBO);
		glVertexAttribPointer(0, 4, GL_UNSIGNED_INT_2_10_10_10_REV, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, rd.normalBO);
		glVertexAttribPointer(1, 4, GL_UNSIGNED_INT_2_10_10_10_REV, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, rd.metaBO);
		glVertexAttribIPointer(2, 4, GL_UNSIGNED_BYTE, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		glDrawArrays(GL_TRIANGLES, 0, rd.vertexCount);
		numVerts += rd.vertexCount;
		drawCalls++;
	}

	void endRender()
	{
		import derelict.opengl3.gl3;
		foreach(x; 0 .. 3)
			glDisableVertexAttribArray(x);
		
		textureArray.unbind;
		effect.unbind;

		glBindVertexArray(0);
	}

	IBlockVoxelTexture getTexture(ushort id) { return textures[id]; }
	IBlockVoxelTexture getTexture(string technical)
	{
		import std.algorithm.searching : find;
		import std.range : takeOne;
		return textures.find!(a => a.technical == technical)[0];
	}

	IBlockVoxelMesh getMesh(MeshID id) { return blockMeshes[id]; }

	enum minimumMeshers = 2;
	@property size_t minMeshers() const { return minimumMeshers; }
	IMesher requestMesher(IChannel!MeshOrder source) { return new Mesher(this, resources, meshBufferHost, source); }
	void returnMesher(IMesher m) {}
}