module square.one.voxelcon.vegetation.processor;

import moxana.graphics.effect;
import square.one.graphics.texture2darray;

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
import std.conv;

import dlib.math;
import derelict.opengl3.gl3;

final class VegetationProcessor : IProcessor {
	mixin(VoxelContentQuick!("vegetation_processor", "Vegetation (processor)", squareOneMod, dylanGrahamName));

	private ubyte id_;
	@property ubyte id() const { return id_; }
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

	IVegetationVoxelTexture[] vegetationTextures;
	private Texture2DArray textureArray;

	this(IVegetationVoxelTexture[] textures) {
		this.vegetationTextures = textures;

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

		string[] textureFiles = new string[](vegetationTextures.length);
		foreach(size_t x, IVegetationVoxelTexture texture; vegetationTextures) {
			texture.id = cast(ubyte)x;
			textureFiles[x] = texture.file;
		}
		textureArray = new Texture2DArray(textureFiles, DifferentSize.shouldResize, GL_NEAREST, GL_NEAREST, true);

		foreach(int x; 0 .. resources.materialCount) {
			IVegetationVoxelMaterial vvm = cast(IVegetationVoxelMaterial)resources.getMaterial(x);
			if(vvm is null) continue;
			vvm.loadTextures(this);
			vegetationMaterials[cast(ushort)x] = vvm;
		}

		vegetationMaterials.rehash;

		foreach(x; 0 .. mesherCount)
			meshers ~= new Mesher(uploadSyncObj, &uploadQueue, resources, this, mbHost);

		glCreateVertexArrays(1, &vao);

		ShaderEntry[] shaders = new ShaderEntry[](2);
		shaders[0] = ShaderEntry(readText(buildPath(getcwd, "assets/shaders/vegetation_voxel.vs.glsl")), GL_VERTEX_SHADER);
		shaders[1] = ShaderEntry(readText(buildPath(getcwd, "assets/shaders/vegetation_voxel.fs.glsl")), GL_FRAGMENT_SHADER);
		effect = new Effect(shaders, VegetationProcessor.stringof);
		effect.bind;
		effect.findUniform("ModelViewProjection");
		effect.findUniform("Model");
		effect.findUniform("Textures");
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
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * Vector3f.sizeof, up.buffer.vertices.ptr, GL_STATIC_DRAW);

			glBindBuffer(GL_ARRAY_BUFFER, rd.cbo);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * ubyte.sizeof * 4, up.buffer.colours.ptr, GL_STATIC_DRAW);

			glBindBuffer(GL_ARRAY_BUFFER, rd.tbo);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * Vector2f.sizeof, up.buffer.texCoords.ptr, GL_STATIC_DRAW);

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

		effect.bind;

		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		glEnableVertexAttribArray(2);

		Texture2DArray.enable;
		glActiveTexture(GL_TEXTURE0);
		textureArray.bind;
		effect["Textures"].set(0);
	}

	void render(Chunk chunk, ref LocalRenderContext lrc) {
		if(isRdNull(chunk)) return;

		RenderData* rd = getRd(chunk);

		Vector3f localPos = chunk.transform.position;
		Matrix4f m = translationMatrix(localPos);
		Matrix4f mvp = lrc.perspective.matrix * lrc.view * m;
		effect["ModelViewProjection"].set(&mvp, true);
		effect["Model"].set(&m, true);

		glBindBuffer(GL_ARRAY_BUFFER, rd.vbo);
		glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, rd.cbo);
		glVertexAttribIPointer(1, 4, GL_UNSIGNED_BYTE, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, rd.tbo);
		glVertexAttribPointer(2, 2, GL_FLOAT, false, 0, null);

		glBindBuffer(GL_ARRAY_BUFFER, 0);

		glDrawArrays(GL_TRIANGLES, 0, rd.vertexCount);
	}

	void endRender() {
		glDisableVertexAttribArray(0);
		glDisableVertexAttribArray(1);
		glDisableVertexAttribArray(2);
		textureArray.unbind;
		Texture2DArray.disable;
		effect.unbind;
		glBindVertexArray(0);
	}

	package IVegetationVoxelMesh[ushort] vegetationMeshes;
	package IVegetationVoxelMaterial[ushort] vegetationMaterials;
	ubyte getTextureID(string technical) {
		foreach(IVegetationVoxelTexture t; vegetationTextures) {
			if(t.technical == technical)
				return t.id;
		}
		return 255;
	}
}

enum MeshType {
	other,
	grassShort,
	grassMedium,
	grassTall,
	flowerShort,
	flowerMedium,
	flowerTall
}

enum int grassShortHeight = 1;
enum int grassMediumHeight = 2;
enum int grassTallHeight = 4;

enum int flowerHeadOffsetMedium = 1;

interface IVegetationVoxelMesh : IVoxelMesh {
	@property MeshType meshType();
	void generateOtherMesh();
}

interface IVegetationVoxelTexture : IVoxelContent {
	@property ubyte id();
	@property void id(ubyte);

	@property string file();
}

Vector3f extractColour(Voxel v) {
	uint col = v.materialData & 0x3_FFFF;
	uint r = col & 0x3F;
	uint g = (col >> 6) & 0x3F;
	uint b = (col >> 12) & 0x3F;
	return Vector3f(r / 63f, g / 63f, b / 63f);
}

void insertColour(Vector3f col, Voxel* v) {
	v.materialData = v.materialData & ~0x3_FFFF;
	uint r = clamp(cast(uint)(col.x * 63), 0, 63);
	uint g = clamp(cast(uint)(col.y * 63), 0, 63);
	uint b = clamp(cast(uint)(col.z * 63), 0, 63);
	uint f = (b << 12) | (g << 6) | r;
	v.materialData = v.materialData | f;
}

enum FlowerRotation : ubyte {
	nz = 0,
	nzpx = 1,
	px = 2,
	pxpz = 3,
	pz = 4,
	nxpz = 5,
	nx = 6,
	nxnz = 7
}

FlowerRotation getFlowerRotation(Voxel v) {
	ubyte twobits = (v.materialData >> 18) & 0x3;
	ubyte onebit = (v.meshData >> 19) & 0x1;
	int total = (onebit << 2) | twobits;
	return cast(FlowerRotation)total;
}

void setFlowerRotation(FlowerRotation fr, Voxel* v) {
	ubyte twobits = cast(ubyte)fr & 0x3;
	ubyte onebit = ((cast(ubyte)fr) >> 2) & 0x1;
	v.materialData = v.materialData & ~(0x3 << 18);
	v.materialData = v.materialData | (twobits << 18);
	v.meshData = v.meshData & ~(0x1 << 19);
	v.meshData = v.meshData | (onebit << 19);
}

interface IVegetationVoxelMaterial : IVoxelMaterial {
	void loadTextures(VegetationProcessor vp);

	@property ubyte grassTexture();
	@property ubyte flowerStorkTexture();
	@property ubyte flowerHeadTexture();

	void applyTexturesOther();
}

struct RenderData {
	uint vbo;
	uint cbo;
	uint tbo;
	ushort vertexCount;

	void create() {
		glGenBuffers(1, &vbo);
		glGenBuffers(1, &cbo);
		glGenBuffers(1, &tbo);
	}

	void cleanup() {
		glDeleteBuffers(1, &vbo);
		glDeleteBuffers(1, &cbo);
		glDeleteBuffers(1, &tbo);
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

			StopWatch sw = StopWatch(AutoStart.yes);
			operateOnChunk(chunk, mb);

			if(mb.vertexCount == 0) {
				mbHost.give(mb);
				chunk.meshBlocking(false, vp.id);
			}
			else {
				sw.stop;
				writeln("Completed vegetation mesh in ", sw.peek.total!"nsecs" / 1_000_000f, "ms. ", mb.vertexCount, " vertices.");

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

					IVegetationVoxelMesh* mesh = v.mesh in vp.vegetationMeshes;
					if(mesh is null) continue;

					Voxel ny = vb.get(x, y - 1, z);
					bool shiftDown = resources.getMesh(ny.mesh).isSideSolid(ny, VoxelSide.py) != SideSolidTable.solid;

					vec3f colour = extractColour(v);

					ubyte[4] colourBytes = [
						cast(ubyte)(colour.x * 255),
						cast(ubyte)(colour.y * 255),
						cast(ubyte)(colour.z * 255),
						0
					];

					IVegetationVoxelMaterial* material = v.material in vp.vegetationMaterials;
					if(material is null) throw new Exception("Error! Material not compatible with vegetation mesh or material of the voxel could not be found! Voxel material: " ~ to!string(v.material));

					if(mesh.meshType == MeshType.grassMedium) {
						colourBytes[3] = material.grassTexture;
						foreach(size_t vid, immutable vec3f vertex; grassPlane) {
							vec3f vertex1 = (vertex * vec3f(1, grassMediumHeight, 1)) * vb.blockskip + vec3i(x, y, z);
							if(shiftDown) vertex1.y -= vb.blockskip;
							vertex1 *= vb.voxelScale;
							vec2f texCoord = grassPlaneTexCoords[vid];
							mb.add(vertex1, colourBytes, texCoord);
						}
					}
					if(mesh.meshType == MeshType.flowerMedium) {
						FlowerRotation fr = getFlowerRotation(v);
						uint materialData = v.materialData;
						uint meshData = v.meshData;

						mat4f rotation = void;
						final switch(fr) {
							case FlowerRotation.nz: rotation = mat4f.rotateY(radians(180f)); break;
							case FlowerRotation.nzpx: rotation = mat4f.rotateY(radians(135f)); break;
							case FlowerRotation.px: rotation = mat4f.rotateY(radians(90f)); break;
							case FlowerRotation.pxpz: rotation = mat4f.rotateY(radians(45f)); break;
							case FlowerRotation.pz: rotation = mat4f.identity; break;
							case FlowerRotation.nxpz: rotation = mat4f.rotateY(radians(315f)); break;
							case FlowerRotation.nx: rotation = mat4f.rotateY(radians(270f)); break;
							case FlowerRotation.nxnz: rotation = mat4f.rotateY(radians(225f)); break;
						}

						colourBytes[3] = material.flowerHeadTexture;
						foreach(size_t vid, immutable vec3f vertex; flowerHead) {
							vec3f vertex1 = (rotation * vec4f(vertex, 1)).xyz;
							vertex1 = (vertex1 + vec3f(0, flowerHeadOffsetMedium, 0)) * vb.blockskip + vec3i(x, y, z);
							vertex1 *= vb.voxelScale;
							vec2f texCoord = flowerHeadTexCoords[vid];
							mb.add(vertex1, colourBytes, texCoord);
						}
						colourBytes[3] = material.flowerStorkTexture;
						foreach(size_t vid, immutable vec3f vertex; flowerStorkMedium) {
							vec3f vertex1 = (rotation * vec4f(vertex, 1)).xyz;
							vertex1 = (vertex1 * vec3f(1, 1, 1)) * vb.blockskip + vec3i(x, y, z);
							vertex1 *= vb.voxelScale;
							vec2f texCoord = flowerStorkMediumTexCoords[vid];
							mb.add(vertex1, colourBytes, texCoord);
						}
					}
				}
			}
		}
	}

	private immutable Vector3f[] flowerHead = [ // facing +Z
		Vector3f(0, 0, 1),
		Vector3f(1, 0, 1),
		Vector3f(1, 1, 0),
		Vector3f(1, 1, 0),
		Vector3f(0, 1, 0),
		Vector3f(0, 0, 1)
	];

	private immutable Vector2f[] flowerHeadTexCoords = [
		Vector2f(0, 0),
		Vector2f(1, 0),
		Vector2f(1, 1),
		Vector2f(1, 1),
		Vector2f(0, 1),
		Vector2f(0, 0)
	];

	private immutable Vector3f[] flowerStorkMedium = [
		Vector3f(0, 0, 0),
		Vector3f(1, 0, 1),
		Vector3f(1, 1, 1),
		Vector3f(1, 1, 1),
		Vector3f(0, 1, 0),
		Vector3f(0, 0, 0),

		Vector3f(1, 0, 0),
		Vector3f(0, 0, 1),
		Vector3f(0, 1, 1),
		Vector3f(0, 1, 1),
		Vector3f(1, 1, 0),
		Vector3f(1, 0, 0),

		Vector3f(0, 1, 0),
		Vector3f(1, 1, 1),
		Vector3f(0, 2, 0),
		Vector3f(1, 1, 0),
		Vector3f(0, 1, 1),
		Vector3f(1, 2, 0)
	];
	
	private immutable Vector2f[] flowerStorkMediumTexCoords = [
		Vector2f(0, 0),
		Vector2f(1, 0),
		Vector2f(1, 0.5),
		Vector2f(1, 0.5),
		Vector2f(0, 0.5),
		Vector2f(0, 0),

		Vector2f(0, 0),
		Vector2f(1, 0),
		Vector2f(1, 0.5),
		Vector2f(1, 0.5),
		Vector2f(0, 0.5),
		Vector2f(0, 0),

		Vector2f(0, 0.5),
		Vector2f(1, 0.5),
		Vector2f(0, 1),
		Vector2f(0, 0.5),
		Vector2f(1, 0.5),
		Vector2f(0, 1)
	];

	private immutable Vector3f[] grassPlane = [
		Vector3f(0, 0, 0.5),
		Vector3f(1, 0, 0.5),
		Vector3f(1, 1, 0.5),
		Vector3f(1, 1, 0.5),
		Vector3f(0, 1, 0.5),
		Vector3f(0, 0, 0.5)
	];

	private immutable Vector2f[] grassPlaneTexCoords = [
		Vector2f(0.25, 0),
		Vector2f(0.75, 0),
		Vector2f(0.75, 1),
		Vector2f(0.75, 1),
		Vector2f(0.25, 1),
		Vector2f(0.25, 0),
	];
}

private class MeshBuffer {
	Vector3f[] vertices;
	ubyte[] colours;
	Vector2f[] texCoords;
	int vertexCount;

	this() {
		vertices.length = 12000;
		colours.length = vertices.length * 4;
		texCoords.length = vertices.length;
	}

	void reset() { vertexCount = 0; }

	void add(Vector3f v, ubyte[4] colour, Vector2f texCoord) {
		vertices[vertexCount] = v;
		//colours[vertexCount * 4 .. vertexCount * 4 + 4] = colour;
		colours[vertexCount * 4] = colour[0];
		colours[vertexCount * 4 + 1] = colour[1];
		colours[vertexCount * 4 + 2] = colour[2];
		colours[vertexCount * 4 + 3] = colour[3];
		texCoords[vertexCount] = texCoord;
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