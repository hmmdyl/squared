module square.one.voxelcon.vegetation.processor;

import moxana.graphics.effect;

import square.one.terrain.resources;
import square.one.terrain.chunk;

import moxana.utils.logger;
import moxana.utils.event;
import square.one.utils.objpool;

import std.container.dlist;
import core.sync.condition;
import core.thread;
import std.datetime.stopwatch;
import core.memory;
import std.file : getcwd, readText;
import std.path : buildPath;

import gfm.math;
import derelict.opengl3.gl3;

final class VegetationProcessor : IProcessor {
	mixin(VoxelContentQuick!("vegetation_processor", "Vegetation (processor)", squareOneMod, dylanGrahamName));

	private ubyte id_;
	@property ubyte id() { return id_; }
	@property void id(ubyte nid) { id_ = nid; }

	private ObjectPool!(RenderData*) renderDataPool;
	
	private MeshBufferHost mbHost;
	private DList!UploadItem uploadQueue;
	private Object uploadSyncObj;

	Resources resources;

	enum int mesherCount = 1;

	private int meshBarrel;
	private Mesher[] meshers;

	private uint vao;
	private Effect effect;

	this() {
		mbHost = new MeshBufferHost;
		uploadSyncObj = new Object;
		renderDataPool = ObjectPool!(RenderData*)(() { return new RenderData; }, 64);
	}

	~this() {
		glDeleteVertexArrays(1, &vao);
	}

	void finaliseResources(Resources res) {
		resources = res;

		foreach(ushort x; 0 .. resources.meshCount) {
			IVegetationVoxelMesh vvm = cast(IVegetationVoxelMesh)resources.getMesh(x);
			if(vvm is null) continue;
			vegetationMeshes[x] = vvm;
		}

		vegetationMeshes.rehash;

		foreach(x; 0 .. mesherCount)
			meshers ~= new Mesher(uploadSyncObj, &uploadQueue, resources, this, mbHost);

		glGenVertexArrays(1, &vao);

		ShaderEntry[] shaders = new ShaderEntry[](2);
		shaders[0] = ShaderEntry(readText(buildPath(getcwd, "assets/shaders/vegetation_voxel.vs.glsl")), GL_VERTEX_SHADER);
		shaders[1] = ShaderEntry(readText(buildPath(getcwd, "assets/shaders/vegetation_voxel.fs.glsl")), GL_FRAGMENT_SHADER);
		effect = new Effect(shaders, VegetationProcessor.stringof);
		effect.bind;
		effect.findUniform("ModelViewProjection");
		effect.findUniform("Model");
		effect.unbind;

		destroy(shaders);
		GC.free(shaders.ptr);
	}

	void meshChunk(IMeshableVoxelBuffer c) {
		synchronized(meshers[meshBarrel].meshSyncObj) {
			c.meshBlocking(true, id_);
			meshers[meshBarrel].meshQueue.insert(c);

			synchronized(meshers[meshBarrel].meshQueueWaiterMutex)
				meshers[meshBarrel].meshQueueWaiter.notify;
		}

		meshBarrel++;
		if(meshBarrel >= mesherCount) meshBarrel = 0;
	}

	void removeChunk(IMeshableVoxelBuffer c) {
		if(isRdNull(c)) return;

		RenderData* rd = getRd(c);
		rd.cleanup;
		renderDataPool.give(rd);

		c.renderData[id_] = null;
	}

	private bool isRdNull(IMeshableVoxelBuffer vb) { return vb.renderData[id_] is null; }
	private RenderData* getRd(IMeshableVoxelBuffer vb) { return cast(RenderData*)vb.renderData[id_]; }

	void updateFromManager() {}

	private void performUploads() {
		bool isEmpty() { synchronized(uploadSyncObj) return uploadQueue.empty; }

		UploadItem getUploadItem() {
			synchronized(uploadSyncObj) {
				UploadItem i = uploadQueue.front;
				uploadQueue.removeFront;
				return i;
			}
		}

		StopWatch sw;
		sw.start;

		while(sw.peek.total!"msecs" < 4 && !isEmpty) {
			if(isEmpty) return;

			UploadItem up = getUploadItem;

			bool hasRd = !isRdNull(up.chunk);
			RenderData* rd;
			if(hasRd) rd = getRd(up.chunk);
			else {
				rd = renderDataPool.get();
				rd.create;
				up.chunk.renderData[id_] = cast(void*)rd;
			}

			rd.vertexCount = cast(ushort)up.buffer.vertexCount;

			glBindBuffer(GL_ARRAY_BUFFER, rd.vbo);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * vec3f.sizeof, up.buffer.vertices.ptr, GL_STATIC_DRAW);
			glBindBuffer(GL_ARRAY_BUFFER, 0);

			up.chunk.meshBlocking(false, id_);

			mbHost.give(up.buffer);
		}
	}

	private void restartCrashedThreads() {
		foreach(ref Mesher mesher; meshers) {
			if(mesher.requiresRestart)
				mesher.restart;
		}
	}

	void prepareRenderShadow(RenderContext context) {}
	void renderShadow(Chunk chunk, ref LocalRenderContext lrc) {}
	void endRenderShadow() {}

	RenderContext rc;

	void prepareRender(RenderContext context) {
		this.rc = context;

		performUploads;
		restartCrashedThreads;

		glBindVertexArray(vao);

		glEnableVertexAttribArray(0);

		effect.bind;
	}

	void render(Chunk chunk, ref LocalRenderContext lrc) {
		if(isRdNull(chunk)) return;

		RenderData* rd = getRd(chunk);

		vec3f localPos = chunk.transform.position;
		mat4f m = mat4f.translation(localPos);
		mat4f mvp = lrc.perspective.matrix * lrc.view * m;
		effect["ModelViewProjection"].set(&mvp, true);
		effect["Model"].set(&m, true);

		glBindBuffer(GL_ARRAY_BUFFER, rd.vbo);
		glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		glDrawArrays(GL_TRIANGLES, 0, rd.vertexCount);
	}

	void endRender() {
		glDisableVertexAttribArray(0);
		effect.unbind;
		glBindVertexArray(0);
	}

	package IVegetationVoxelMesh[ushort] vegetationMeshes;
}

enum MeshType {
	other,
	grassShort,
	grassMedium,
	grassTall,
	flower
}

interface IVegetationVoxelMesh : IVoxelMesh {
	@property MeshType meshType();
	void generateOtherMesh();
}

interface IVegetationVoxelMaterial : IVoxelMaterial {
	void loadTextures();
}

struct RenderData {
	uint vbo;
	ushort vertexCount;

	void create() {
		glGenBuffers(1, &vbo);
	}

	void cleanup() {
		glDeleteBuffers(1, &vbo);
	}
}

private struct UploadItem {
	IMeshableVoxelBuffer chunk;
	MeshBuffer buffer;

	@disable this();

	this(IMeshableVoxelBuffer chunk, MeshBuffer buffer) {
		this.chunk = chunk;
		this.buffer = buffer;
	}
}

private class Mesher {
	Object meshSyncObj;
	DList!IMeshableVoxelBuffer meshQueue;
	Condition meshQueueWaiter;
	Mutex meshQueueWaiterMutex;

	Object uploadSyncObj;
	DList!(UploadItem)* uploadQueue;

	Resources resources;
	VegetationProcessor vp;
	MeshBufferHost mbHost;

	bool busy;
	bool requiresRestart;

	private Thread thread;

	this(Object uploadSyncObj, DList!(UploadItem)* uploadQueue, Resources resources, VegetationProcessor vp, MeshBufferHost mbHost) {
		this.meshSyncObj = new Object;
		this.meshQueue = DList!IMeshableVoxelBuffer();
		this.meshQueueWaiterMutex = new Mutex;
		this.meshQueueWaiter = new Condition(meshQueueWaiterMutex);

		this.uploadSyncObj = uploadSyncObj;
		this.uploadQueue = uploadQueue;
		this.resources = resources;
		this.vp = vp;
		this.mbHost = mbHost;

		thread = new Thread(&workerFuncRoot);
		thread.isDaemon = true;
		thread.name = VegetationProcessor.stringof ~ " " ~ Mesher.stringof ~ " thread";
		thread.start;
	}

	void restart() {
		requiresRestart = false;
		thread.start;
	}

	private IMeshableVoxelBuffer chunk;
	private MeshBuffer mb;

	private void workerFuncRoot() {
		try workerFuncProper;
		catch(Throwable e) {
			import std.conv : to;

			char[] error = "Exception thrown in thread \"" ~ thread.name ~ "\". Contents: " ~ e.message ~ ". Line: " ~ to!string(e.line) ~ "\nStacktrace: " ~ e.info.toString;
			writeLog(LogType.error, cast(string)error);
			writeLog("This thread will be replaced. Resetting chunk. It will be notified to reattempt meshing.");

			if(chunk !is null) {
				chunk.meshBlocking(false, vp.id_);
				chunk.needsMesh = true;
			}
			chunk = null;

			if(mb !is null) {
				mb.reset;
				mbHost.give(mb);
			}
			mb = null;

			requiresRestart = true;
		}
	}

	private void workerFuncProper() {
		while(true) {
			busy = false;

			chunk = null;
			mb = null;

			bool meshQueueEmpty = false;
			synchronized(meshSyncObj) meshQueueEmpty = meshQueue.empty;

			if(meshQueueEmpty)
				synchronized(meshQueueWaiterMutex)
					meshQueueWaiter.wait;
			synchronized(meshSyncObj) {
				chunk = meshQueue.front;
				meshQueue.removeFront;
			}

			if(chunk is null) continue;

			busy = true;

			mb = null;
			do
				mb = mbHost.request;
			while(mb is null);

			operateOnChunk(chunk, mb);

			if(mb.vertexCount == 0) {
				mbHost.give(mb);
				chunk.meshBlocking(false, vp.id);
			}
			else {
				synchronized(uploadSyncObj) {
					uploadQueue.insert(UploadItem(chunk, mb));
				}
			}

			mb = null;
			chunk = null;
		}
	}

	private void operateOnChunk(IMeshableVoxelBuffer vb, MeshBuffer mb) {
		for(int x = 0; x < ChunkData.chunkDimensions; x += vb.blockskip) {
			for(int y = 0; y < ChunkData.chunkDimensions; y += vb.blockskip) {
				for(int z = 0; z < ChunkData.chunkDimensions; z += vb.blockskip) {
					Voxel v = vb.get(x, y, z);
					Voxel ny = vb.get(x, y - 1, z);
					bool shiftDown = resources.getMesh(ny.mesh).isSideSolid(ny, VoxelSide.py) != SideSolidTable.solid;

					IVegetationVoxelMesh* mesh = v.mesh in vp.vegetationMeshes;
					if(mesh is null) continue;

					if(mesh.meshType == MeshType.grassMedium) {
						foreach(immutable vec3f vertex; grassMedium) {
							vec3f vertex1 = vertex * vb.blockskip + vec3i(x, y, z);
							if(shiftDown) vertex1.y -= vb.blockskip;
							vertex1 *= vb.voxelScale;
							mb.add(vertex1);
						}
					}
				}
			}
		}
	}

	private immutable vec3f[] grassMedium = [
		vec3f(0, 0, 0.5),
		vec3f(0.8, 0, 0.5),
		vec3f(0.8, 1, 0.5),
		vec3f(0.8, 1, 0.5),
		vec3f(0, 1, 0.5),
		vec3f(0, 0, 0.5)
	];
}

private class MeshBuffer {
	vec3f[] vertices;
	int vertexCount;

	this() {
		vertices.length = 12000;
	}

	void reset() { vertexCount = 0; }

	void add(vec3f v) {
		vertices[vertexCount] = v;
		vertexCount++;
	}
}

private class MeshBufferHost {
	enum int meshCount = 6;

	private DList!MeshBuffer meshBuffers;

	this() {
		foreach(x; 0 .. meshCount)
			meshBuffers.insertBack(new MeshBuffer());
	}

	MeshBuffer request() {
		synchronized(this) {
			if(!meshBuffers.empty) {
				auto mb = meshBuffers.back;
				meshBuffers.removeBack;
				return mb;
			}

			return null;
		}
	}

	void give(MeshBuffer mb) {
		mb.reset;

		synchronized(this) {
			meshBuffers.insertBack(mb);
		}
	}
}