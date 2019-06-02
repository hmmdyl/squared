module square.one.voxelcon.block.processor;

public import square.one.terrain.resources;

import dlib.math;

import std.container.dlist;
import core.thread;
import core.sync.condition;
import std.datetime.stopwatch;

import derelict.opengl3.gl3;

import moxana.graphics.effect;
import square.one.graphics.texture2darray;
import square.one.utils.objpool;

import std.experimental.allocator;
import std.experimental.allocator.mallocator;

import std.experimental.logger;

__gshared bool threadsActive;

final class BlockProcessor : IProcessor {
	private ubyte id_;
	@property ubyte id() { return id_; }
	@property void id(ubyte nid) { id_ = nid; }
	
	@property string technical() { return "block_processor"; }
	@property string display() { return "Block (processor)"; }
	@property string mod() { return squareOneMod; }
	@property string author() { return dylanGrahamName; }
	
	private IBlockVoxelMesh[int] blockMeshes;
	
	private Object meshSyncObj;
	private DList!(IMeshableVoxelBuffer)* meshQueue;
	private Condition meshQueueWaiter;
	private Mutex meshQueueWaiterMutex;
	
	private Object uploadSyncObj;
	private DList!(UploadItem)* uploadQueue;
	
	private BlockMeshBufferHost host;
	
	Resources resources;
	
	private enum mesherCount = 1;
	private Mesher[] meshers = null;
	
	private uint vao;
	private Effect effect;
	private Effect shadowEffect;
	
	private ObjectPool!(RenderData*) renderDataPool;
	
	private IBlockVoxelTexture[] textures;
	private Texture2DArray textureArray;
	
	this(IBlockVoxelTexture[] textures) {
		this.textures = textures;
		foreach(ushort texID, texture; this.textures) {
			texture.id = texID;
		}
		
		threadsActive = true;

		meshSyncObj = new Object();
		meshQueue = new DList!(IMeshableVoxelBuffer)();
		meshQueueWaiterMutex = new Mutex();
		meshQueueWaiter = new Condition(meshQueueWaiterMutex);
		uploadSyncObj = new Object();
		uploadQueue = new DList!(UploadItem)();
		
		host = new BlockMeshBufferHost();
		
		renderDataPool = ObjectPool!(RenderData*)(() { return new RenderData(); }, 8192);
	}
	
	void finaliseResources(Resources res) {
		resources = res;
		
		foreach(int x; 0 .. res.meshCount) {
			IBlockVoxelMesh bm = cast(IBlockVoxelMesh)res.getMesh(x);
			if(bm is null)
				continue;
			
			blockMeshes[x] = bm;
		}
		
		blockMeshes.rehash();
		
		string[] textureFiles = new string[](textures.length);
		foreach(int x, IBlockVoxelTexture texture; textures) {
			textureFiles[x] = texture.file;
		}
		
		textureArray = new Texture2DArray(textureFiles, DifferentSize.shouldResize, GL_NEAREST_MIPMAP_LINEAR, GL_NEAREST, true);
		
		foreach(int x; 0 .. res.materialCount) {
			IBlockVoxelMaterial bm = cast(IBlockVoxelMaterial)res.getMaterial(x);
			if(bm is null) 
				continue;
			
			bm.loadTextures(this);
		}
		
		meshers.length = mesherCount;
		foreach(int x; 0 .. mesherCount) 
			meshers[x] = new Mesher(meshSyncObj, meshQueue, meshQueueWaiter, meshQueueWaiterMutex, uploadSyncObj, uploadQueue, 
			host, res, id_, &lowestMeshTime, &highestMeshTime, &averageMeshTime);
		
		glCreateVertexArrays(1, &vao);
		
		ShaderEntry[] shaders = new ShaderEntry[](2);
		shaders[0] = ShaderEntry(vertexShader, GL_VERTEX_SHADER);
		shaders[1] = ShaderEntry(fragmentShader, GL_FRAGMENT_SHADER);
		effect = new Effect(shaders, BlockProcessor.stringof);
		effect.bind();
		effect.findUniform("ModelViewProjection");
		effect.findUniform("Fit10bScale");
		effect.findUniform("Diffuse");
		effect.findUniform("Model");
		effect.findUniform("ModelView");
		effect.unbind();

		shaders[0] = ShaderEntry(vertexShadowShader, GL_VERTEX_SHADER);
		shaders[1] = ShaderEntry(fragmentShadowShader, GL_FRAGMENT_SHADER);
		shadowEffect = new Effect(shaders, BlockProcessor.stringof ~ " SHADOW");
		shadowEffect.bind();
		shadowEffect.findUniform("ModelViewProjection");
		shadowEffect.unbind();
	}
	
	void meshChunk(IMeshableVoxelBuffer c) {
		// ***** IDEA 31/12/17 *****
		// TODO: sort chunk based on distance to camera.
		
		synchronized(meshSyncObj) {
			c.meshBlocking(true, id_);
			meshQueue.insert(c);
			
			synchronized(meshQueueWaiterMutex)
				meshQueueWaiter.notify(); 
		}
	}
	
	bool isRdNull(IMeshableVoxelBuffer chunk) { return chunk.renderData[id_] is null; }
	RenderData* getRdOfChunk(IMeshableVoxelBuffer chunk) { return cast(RenderData*)chunk.renderData[id_]; }
	
	void removeChunk(IMeshableVoxelBuffer chunk) {
		// ***** AS OF 31/12/17 *****
		// BlockProcessor does not contain info on a chunk besides the structs referenced by the chunk itself. 
		// Therefore, this function only needs to free such data referenced by the chunk.
		
		if(isRdNull(chunk)) return;
		
		RenderData* rd = getRdOfChunk(chunk);
		rd.destroy();
		renderDataPool.give(rd);
		
		chunk.renderData[id_] = null;
	}
	
	StopWatch uploadItemSw = StopWatch(AutoStart.no);
	
	private uint[] compressionBuffer = new uint[](vertsFull);
	
	private void performUploads() {
		bool isEmpty() {
			synchronized(uploadSyncObj) {
				return uploadQueue.empty;
			}
		}
		
		UploadItem getFromUploadQueue() {
			synchronized(uploadSyncObj) {
				if(uploadQueue.empty) throw new Exception("die");
				UploadItem i = uploadQueue.front;
				uploadQueue.removeFront();
				return i;
			}
		}
		
		uploadItemSw.start();
		
		while(uploadItemSw.peek().total!"msecs" < 8 && !isEmpty()){
			if(isEmpty) return;
			
			UploadItem upItem = getFromUploadQueue();
			
			bool hasRd = !isRdNull(upItem.chunk);
			RenderData* rd;
			if(hasRd) {
				rd = getRdOfChunk(upItem.chunk);
			}
			else {
				rd = renderDataPool.get();
				rd.create();
				upItem.chunk.renderData[id_] = cast(void*)rd;
			}
			
			rd.vertexCount = upItem.bmb.vertexCount;
			
			rd.chunkMax = ChunkData.chunkDimensions * ChunkData.voxelScale;
			float invCM = 1f / rd.chunkMax;
			rd.fit10bScale = 1023f * invCM;
			
			/*foreach(int i; 0 .. upItem.bmb.vertexCount) {
				vec3f v = upItem.bmb.vertices[i];
				
				float vx = clamp(v.x, 0f, rd.chunkMax) * rd.fit10bScale;
				uint vxU = cast(uint)vx & 1023;
				
				float vy = clamp(v.y, 0f, rd.chunkMax) * rd.fit10bScale;
				uint vyU = cast(uint)vy & 1023;
				vyU <<= 10;
				
				float vz = clamp(v.z, 0f, rd.chunkMax) * rd.fit10bScale;
				uint vzU = cast(uint)vz & 1023;
				vzU <<= 20;
				
				compressionBuffer[i] = vxU | vyU | vzU;
			}
			
			glBindBuffer(GL_ARRAY_BUFFER, rd.vbo);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, compressionBuffer.ptr, GL_STATIC_DRAW);*/

			glBindBuffer(GL_ARRAY_BUFFER, rd.vbo);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * Vector3f.sizeof, upItem.bmb.vertices.ptr, GL_STATIC_DRAW);
			
			foreach(int i; 0 .. upItem.bmb.vertexCount) {
				Vector3f n = upItem.bmb.normals[i];
				
				float nx = (((clamp(n.x, -1f, 1f) + 1f) * 0.5f) * 1023f);
				uint nxU = cast(uint)nx & 1023;
				
				float ny = (((clamp(n.y, -1f, 1f) + 1f) * 0.5f) * 1023f);
				uint nyU = cast(uint)ny & 1023;
				nyU <<= 10;
				
				float nz = (((clamp(n.z, -1f, 1f) + 1f) * 0.5f) * 1023f);
				uint nzU = cast(uint)nz & 1023;
				nzU <<= 20;
				
				compressionBuffer[i] = nxU | nyU | nzU;
			}
			
			glBindBuffer(GL_ARRAY_BUFFER, rd.nbo);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, compressionBuffer.ptr, GL_STATIC_DRAW);
			
			glBindBuffer(GL_ARRAY_BUFFER, rd.metabo);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, upItem.bmb.meta.ptr, GL_STATIC_DRAW);
			glBindBuffer(GL_ARRAY_BUFFER, 0);
			
			upItem.chunk.meshBlocking(false, id_);
			
			host.give(upItem.bmb);
		}

		uploadItemSw.stop();
		uploadItemSw.reset();
	}
	
	double lowestMeshTime = 0, highestMeshTime = 0, averageMeshTime = 0;
	
	RenderContext renderContext;
	void prepareRender(RenderContext rc) {
		performUploads();
		glBindVertexArray(vao);
		
		effect.bind();
		
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		glEnableVertexAttribArray(2);
		
		this.renderContext = rc;
		
		Texture2DArray.enable();
		glActiveTexture(GL_TEXTURE0);
		textureArray.bind();
		effect["Diffuse"].set(0);

		//glEnable(GL_DEPTH_TEST);
		//glDepthFunc(GL_LESS);
	}

	void prepareRenderShadow(RenderContext rc)
	{
		glBindVertexArray(vao);
		shadowEffect.bind();
		glEnableVertexAttribArray(0);
		this.renderContext = rc;
	}
	
	void render(Chunk chunk, ref LocalRenderContext lrc) {
		if(isRdNull(chunk)) return;
		
		RenderData* rd = getRdOfChunk(chunk);
		
		//vec3f localPos = cast(vec3f)renderContext.localiseCoord(cast(vec3d)chunk.position.toVec3f());
		Vector3f localPos = chunk.transform.position;
		Matrix4f m = translationMatrix(localPos);
		Matrix4f mvp = lrc.perspective.matrix * lrc.view * m;
		Matrix4f mv = lrc.view * m;
		effect["ModelViewProjection"].set(&mvp, true);
		effect["Fit10bScale"].set(rd.fit10bScale);
		effect["Model"].set(&m, true);
		effect["ModelView"].set(&mv, true);
		
		glBindBuffer(GL_ARRAY_BUFFER, rd.vbo);
		//glVertexAttribPointer(0, 4, GL_UNSIGNED_INT_2_10_10_10_REV, false, 0, null);
		glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, rd.nbo);
		glVertexAttribPointer(1, 4, GL_UNSIGNED_INT_2_10_10_10_REV, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, rd.metabo);
		glVertexAttribIPointer(2, 4, GL_UNSIGNED_BYTE, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		
		glDrawArrays(GL_TRIANGLES, 0, rd.vertexCount);
	}

	void renderShadow(Chunk chunk, ref LocalRenderContext lrc)
	{
		if(isRdNull(chunk)) return;

		RenderData* rd = getRdOfChunk(chunk);

		Vector3f localPos = chunk.transform.position;
		Matrix4f m = translationMatrix(localPos);
		Matrix4f mvp = lrc.perspective.matrix * lrc.view * m;
		shadowEffect["ModelViewProjection"].set(&mvp, true);

		glBindBuffer(GL_ARRAY_BUFFER, rd.vbo);
		glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		glDrawArrays(GL_TRIANGLES, 0, rd.vertexCount);
	}

	void endRender() {
		//glDisable(GL_DEPTH_TEST);
		glDisableVertexAttribArray(2);
		glDisableVertexAttribArray(1);
		glDisableVertexAttribArray(0);
		
		textureArray.unbind;
		Texture2DArray.disable;
		effect.unbind();
		
		glBindVertexArray(0);
	}

	void endRenderShadow()
	{
		glDisableVertexAttribArray(0);
		shadowEffect.unbind();
		glBindVertexArray(0);
	}

	void updateFromManager() {}
	
	@property IBlockVoxelTexture getTexture(ushort id) { return textures[id]; }
	@property IBlockVoxelTexture getTexture(string technical) { // Warning slow!
		foreach(texture; textures)
			if(texture.technical == technical)
				return texture;
		throw new Exception(technical ~ " not found.");
	}

	@property uint numMeshThreadsBusy() {
		uint n = 0;
		foreach(Mesher m; meshers) {
			if(m.busy)
				n++;
		}
		return n;
	}
}

interface IBlockVoxelMesh  : IVoxelMesh {
	void generateMesh(Voxel target, int voxelSkip, ref Voxel[6] neigbours, ref SideSolidTable[6] sidesSolid, Vector3i coord, ref Vector3f[64] verts, ref Vector3f[64] normals, out int vertCount);
}

interface IBlockVoxelMaterial : IVoxelMaterial {
	void loadTextures(scope BlockProcessor bp);
	void generateTextureIDs(int vlength, ref Vector3f[64] vertices, ref Vector3f[64] normals, ref ushort[64] textureIDs);
}

interface IBlockVoxelTexture : IVoxelContent {
	@property ushort id();
	@property void id(ushort);
	
	@property string file();
}

struct RenderData {
	uint vbo, nbo, metabo;
	int vertexCount;
	
	float chunkMax, fit10bScale;
	
	void create() {
		glGenBuffers(1, &vbo);
		glGenBuffers(1, &nbo);
		glGenBuffers(1, &metabo);
		vertexCount = 0;
	}
	
	void destroy() {
		glDeleteBuffers(1, &vbo);
		glDeleteBuffers(1, &nbo);
		glDeleteBuffers(1, &metabo);
		vertexCount = 0;
		chunkMax = float.nan;
		fit10bScale = float.nan;
	}
}

private struct UploadItem {
	enum CommandType {
		gpuupload,
		remove
	}

	IMeshableVoxelBuffer chunk;
	BlockMeshBuffer bmb;
	
	this(IMeshableVoxelBuffer chunk, BlockMeshBuffer bmb) {
		this.chunk = chunk;
		this.bmb = bmb;
	}
}

private class Mesher {
	Object meshSyncObj;
	DList!(IMeshableVoxelBuffer)* meshQueue;
	Condition meshQueueWaiter;
	Mutex meshQueueWaiterMutex;
	
	Object uploadSyncObj;
	DList!(UploadItem)* uploadQueue;
	
	BlockMeshBufferHost host;
	
	Resources resources;
	
	ubyte procID;

	bool busy;
	
	double* lowestMeshTime;
	double* highestMeshTime;
	double* averageMeshTime;
	
	private Thread thread;
	
	this(Object meshSyncObj, DList!(IMeshableVoxelBuffer)* meshQueue, Condition waiter, Mutex meshQueueWaiterMutex, Object uploadSyncObj, 
		DList!(UploadItem)* uploadQueue, BlockMeshBufferHost host, Resources resources, ubyte procID, 
		double* lowestMeshTime, double* highestMeshTime, double* averageMeshTime) {
		this.meshSyncObj = meshSyncObj;
		this.meshQueue = meshQueue;
		this.meshQueueWaiter = waiter;
		this.meshQueueWaiterMutex = meshQueueWaiterMutex;
		this.uploadSyncObj = uploadSyncObj;
		this.uploadQueue = uploadQueue;
		this.host = host;
		this.resources = resources;
		this.procID = procID;
		this.lowestMeshTime = lowestMeshTime;
		this.highestMeshTime = highestMeshTime;
		this.averageMeshTime = averageMeshTime;
		
		thread = new Thread(&workerFunc);
		thread.isDaemon = true;
		thread.name = "Block mesher thread";
		thread.start();
	}
	
	private void workerFunc() {
		try workerFuncProper;
		catch(Throwable e) {
			import std.conv : to;
			import moxana.utils.logger;

			char[] error = "Exception thrown in thread \"" ~ thread.name ~ "\". Contents: " ~ e.message ~ ". Line: " ~ to!string(e.line) ~ "\nStacktrace: " ~ e.info.toString;
			writeLog(LogType.error, cast(string)error);
		}
	}

	private void workerFuncProper() {
		Vector3f[64] verts, normals;
		ushort[64] textureIDs;
		
		StopWatch sw = StopWatch(AutoStart.no);
		
		while(true) {
			busy = false;
			// ***** IDEA 30/12/17 *****
			// IDEA: have a wait timeout. When timed out, repurpose thread to run jobs. When job is done
			// return as a mesher and wait for chunk.
			
			IMeshableVoxelBuffer chunk = null;
			
			//bool n = true;
			//if(n) throw new Exception("Allahu akbar!");
			
			bool meshQueueEmpty = false;
			synchronized(meshSyncObj) {
				meshQueueEmpty = meshQueue.empty;
			}
			
			if(meshQueueEmpty) {
				synchronized(meshQueueWaiterMutex) {
					meshQueueWaiter.wait();
				}
			}
				
			synchronized(meshSyncObj) {
				chunk = meshQueue.front;
				meshQueue.removeFront();
			}
			
			if(chunk is null)
				continue;

			busy = true;

			sw.start();
			
			BlockMeshBuffer bmb;
			while(bmb is null)
				bmb = host.request(MeshSize.small);
			
			void addVert(Vector3f vert, Vector3f normal, uint meta) {
				if(bmb.ms == MeshSize.small) {
					if(bmb.vertexCount + 1 >= vertsSmall) {
						BlockMeshBuffer nbmb;
						while(nbmb is null)
							nbmb = host.request(MeshSize.medium);
						
						copyBuffer(bmb, nbmb);
						
						host.give(bmb);
						bmb = nbmb;
					}
				}
				else if(bmb.ms == MeshSize.medium) {
					if(bmb.vertexCount + 1 >= vertsMedium) {
						BlockMeshBuffer nbmb;
						while(nbmb is null)
							nbmb = host.request(MeshSize.full);
						
						copyBuffer(bmb, nbmb);
						
						host.give(bmb);
						bmb = nbmb;
					}
				}
				else {
					if(bmb.vertexCount + 1 >= vertsFull) {
						//string exp = "Chunk (" ~ chunk.toString() ~ ") is too complex to mesh. Error: too many vertices for buffer.";
						//throw new Exception(exp);
					}
				}

				import std.conv : to;
				if(bmb.vertexCount + 1 == vertsSmall) { log("Requires more than " ~ to!string(vertsSmall) ~ " vertices."); }

				bmb.add(vert, normal, meta);
			}
			
			for(int x = 0; x < ChunkData.chunkDimensions; x += chunk.blockskip) {
				for(int y = 0; y < ChunkData.chunkDimensions; y += chunk.blockskip)  {
					for(int z = 0; z < ChunkData.chunkDimensions; z += chunk.blockskip)  {
						Voxel v = chunk.get(x, y, z);
						
						IBlockVoxelMesh bvm = cast(IBlockVoxelMesh)resources.getMesh(v.mesh);
						if(bvm is null) continue;

						Voxel[6] neighbours;
						SideSolidTable[6] isSidesSolid;
						
						neighbours[VoxelSide.nx] = chunk.get(x - 1, y, z);
						neighbours[VoxelSide.px] = chunk.get(x + 1, y, z);
						neighbours[VoxelSide.ny] = chunk.get(x, y - 1, z);
						neighbours[VoxelSide.py] = chunk.get(x, y + 1, z);
						neighbours[VoxelSide.nz] = chunk.get(x, y, z - 1);
						neighbours[VoxelSide.pz] = chunk.get(x, y, z + 1);
						
						isSidesSolid[VoxelSide.nx] = resources.getMesh(neighbours[VoxelSide.nx].mesh).isSideSolid(neighbours[VoxelSide.nx], VoxelSide.px);
						isSidesSolid[VoxelSide.px] = resources.getMesh(neighbours[VoxelSide.px].mesh).isSideSolid(neighbours[VoxelSide.px], VoxelSide.nx);
						isSidesSolid[VoxelSide.ny] = resources.getMesh(neighbours[VoxelSide.ny].mesh).isSideSolid(neighbours[VoxelSide.ny], VoxelSide.py);
						isSidesSolid[VoxelSide.py] = resources.getMesh(neighbours[VoxelSide.py].mesh).isSideSolid(neighbours[VoxelSide.py], VoxelSide.ny);
						isSidesSolid[VoxelSide.nz] = resources.getMesh(neighbours[VoxelSide.nz].mesh).isSideSolid(neighbours[VoxelSide.nz], VoxelSide.pz);
						isSidesSolid[VoxelSide.pz] = resources.getMesh(neighbours[VoxelSide.pz].mesh).isSideSolid(neighbours[VoxelSide.pz], VoxelSide.nz);
								
						int vertCount;
						bvm.generateMesh(v, chunk.blockskip, neighbours, isSidesSolid, Vector3i(x, y, z), verts, normals, vertCount);
						
						IBlockVoxelMaterial bvMat = cast(IBlockVoxelMaterial)resources.getMaterial(v.material);
						if(bvMat is null) writeln(":FUYC");
						bvMat.generateTextureIDs(vertCount, verts, normals, textureIDs);
						
						foreach(int i; 0 .. vertCount) {
							addVert(verts[i] * ChunkData.voxelScale, normals[i], textureIDs[i] & 2047);
						}
					}
				}
			}
			
			sw.stop();
			
			synchronized(uploadSyncObj) {
				if(bmb.vertexCount == 0) {
					host.give(bmb);
					chunk.meshBlocking(false, procID);
					
					// TODO: if this is a *re*mesh, delete render data.
				}
				else {
					import std.stdio;
					writeln("Add chunk to upload queue. verts: ", bmb.vertexCount, " time: ", sw.peek().total!"nsecs"() / 1_000_000f);
					import moxana.utils.logger;
					import std.conv;

					double meshTime = sw.peek().total!"nsecs"() / 1_000_000.0;
					if(meshTime < *lowestMeshTime || *lowestMeshTime == 0) {
						*lowestMeshTime = meshTime;
						writeLogDebugInfo("New lowest block mesh time is " ~ to!string(meshTime) ~ "ms with " ~ to!string(bmb.vertexCount) ~ "vertices.");
					}
					if(meshTime > *highestMeshTime || *highestMeshTime == 0) {
						*highestMeshTime = meshTime;
						writeLogDebugInfo("New highest block mesh time is " ~ to!string(meshTime) ~ "ms with " ~ to!string(bmb.vertexCount) ~ "vertices.");	
					}

					if(*averageMeshTime == 0)
						*averageMeshTime = meshTime;
					else {
						*averageMeshTime += meshTime;
						*averageMeshTime *= 0.5;
					}

					uploadQueue.insert(UploadItem(chunk, bmb));
				}
			}
			
			sw.reset();
		}
	}
}

private {
	enum MeshSize {
		small,
		medium,
		full
	}
	
	enum int vertsSmall = 8_192;
	enum int vertsSmallMemoryPerArr = vertsSmall * Vector3f.sizeof;
	
	enum int vertsMedium = 24_576;
	enum int vertsMediumMemoryPerArr = vertsMedium * Vector3f.sizeof;
	
	enum int vertsFull = 147_456;
	enum int vertsFullMemoryPerArr = vertsFull * Vector3f.sizeof;
}

private void copyBuffer(BlockMeshBuffer smaller, BlockMeshBuffer bigger) 
in {
	if(smaller.ms == MeshSize.small)
		assert(bigger.ms == MeshSize.medium || bigger.ms == MeshSize.full);
	if(smaller.ms == MeshSize.medium)
		assert(bigger.ms == MeshSize.full);
	assert(smaller.ms != MeshSize.full);
}
body {
	foreach(int v; 0 .. smaller.vertexCount) {
		bigger.add(smaller.vertices[v], smaller.normals[v], smaller.meta[v]);
	}
}

private class BlockMeshBuffer{
	Vector3f[] vertices;
	Vector3f[] normals;
	uint[] meta;
	
	int vertexCount;
	
	const MeshSize ms;
	
	this(MeshSize ms) {
		this.ms = ms;
		
		if(ms == MeshSize.small) {
			vertices.length = vertsSmall;
			normals.length = vertsSmall;
			meta.length = vertsSmall;
		}
		if(ms == MeshSize.medium) {
			vertices.length = vertsMedium;
			normals.length = vertsMedium;
			meta.length = vertsMedium;
		}
		if(ms == MeshSize.full) {
			vertices.length = vertsFull;
			normals.length = vertsFull;
			meta.length = vertsFull;
		}
	}
	
	void add(Vector3f vert, Vector3f normal, uint meta) {
		vertices[vertexCount] = vert;
		normals[vertexCount] = normal;
		this.meta[vertexCount] = meta;
		vertexCount++;
	}
	
	void reset() {
		vertexCount = 0;
	}
}

import std.container.dlist;

private class BlockMeshBufferHost {
	enum int smallMeshCount = 20;
	enum int mediumMeshCount = 10;
	enum int fullMeshCount = 2;
	
	private DList!(BlockMeshBuffer) smallMeshes;
	private DList!(BlockMeshBuffer) mediumMeshes;
	private DList!(BlockMeshBuffer) fullMeshes;
	
	this() {
		foreach(int x; 0 .. smallMeshCount) 
			smallMeshes.insertBack(new BlockMeshBuffer(MeshSize.small));
		foreach(int x; 0 .. mediumMeshCount)
			mediumMeshes.insertBack(new BlockMeshBuffer(MeshSize.medium));
		foreach(int x; 0 .. fullMeshCount)
			fullMeshes.insertBack(new BlockMeshBuffer(MeshSize.full));
	}
	
	BlockMeshBuffer request(MeshSize m) {
		synchronized(this) {
			if(m == MeshSize.small) {
				if(!smallMeshes.empty) {
					auto bmb = smallMeshes.back;
					smallMeshes.removeBack();
					return bmb;
				}
			}
			if(m == MeshSize.medium) {
				if(!mediumMeshes.empty) {
					auto bmb = mediumMeshes.back;
					mediumMeshes.removeBack();
					return bmb;
				}
			}
			if(m == MeshSize.full) {
				if(!fullMeshes.empty) {
					auto bmb = fullMeshes.back;
					fullMeshes.removeBack();
					return bmb;
				}
			}
			
			return null;
		}
	}
	
	void give(BlockMeshBuffer bmb) {
		synchronized(this) {
			bmb.reset();
			
			if(bmb.ms == MeshSize.small) {
				smallMeshes.insertBack(bmb);
			}
			if(bmb.ms == MeshSize.medium) {
				mediumMeshes.insertBack(bmb);
			}
			if(bmb.ms == MeshSize.full) {
				fullMeshes.insertBack(bmb);
			}
		}
	}
}

private immutable string vertexShader = "
#version 400 core

layout(location = 0) in vec3 Vertex;
layout(location = 1) in vec3 Normal;
layout(location = 2) in ivec4 Meta;

out vec3 fNormal;
flat out float fTexID;
out vec2 fTexCoordX;
out vec2 fTexCoordY;
out vec2 fTexCoordZ;
out vec3 fWorldPos;

uniform mat4 ModelViewProjection;
uniform mat4 Model;
uniform mat4 ModelView;

uniform float Fit10bScale;

void main() {
    //vec3 vert = Vertex.xyz / Fit10bScale;
    vec3 vert = Vertex.xyz;
    gl_Position = ModelViewProjection * vec4(vert, 1);
    fNormal = (Normal.xyz / 1023) * 2 - 1;
    fNormal = normalize(fNormal);

    fTexCoordX = vert.zy;
    fTexCoordY = vert.xz;
    fTexCoordZ = vert.xy;

    fTexID = Meta.x | (Meta.y << 8);

    fWorldPos = (ModelView * vec4(vert, 1)).xyz;
}
";

private immutable string fragmentShader = "
#version 400 core
#extension GL_EXT_texture_array : enable

in vec3 fNormal;
flat in float fTexID;
in vec2 fTexCoordX;
in vec2 fTexCoordY;
in vec2 fTexCoordZ;
in vec3 fWorldPos;

layout(location = 1) out vec3 WorldPositionOut;
layout(location = 0) out vec3 DiffuseOut;
layout(location = 2) out vec3 NormalOut;

uniform sampler2DArray Diffuse;

void main() {
    vec3 n = fNormal * fNormal;
    vec4 texel = texture2DArray(Diffuse, vec3(fTexCoordX, fTexID)) * n.x +
                 texture2DArray(Diffuse, vec3(fTexCoordY, fTexID)) * n.y +
                 texture2DArray(Diffuse, vec3(fTexCoordZ, fTexID)) * n.z;

    WorldPositionOut = fWorldPos;
    DiffuseOut = texel.rgb;
    DiffuseOut = vec3(1);
    NormalOut = fNormal;
}
";

private immutable string vertexShadowShader = "
#version 400 core

layout(location = 0) in vec3 Vertex;

uniform mat4 ModelViewProjection;

void main() 
{
    gl_Position = ModelViewProjection * vec4(Vertex, 1);
}
";

private immutable string fragmentShadowShader = "
#version 400 core

layout(location = 0) out vec3 Fragment;

void main()
{
    Fragment = vec3(1);
}
";
