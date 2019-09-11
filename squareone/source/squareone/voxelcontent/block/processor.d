module squareone.voxelcontent.block.processor;

import squareone.voxel;
import squareone.util.spec;
import squareone.voxelcontent.block.types;
import moxane.core;
import moxane.graphics.effect;
import moxane.graphics.renderer;
import moxane.graphics.texture : Texture2DArray, Filter;
import moxane.graphics.log;
import moxane.utils.pool;

import dlib.math;

import std.container.dlist;
import std.datetime.stopwatch;
import core.thread;
import core.sync.mutex;
import core.sync.condition;

final class BlockProcessor : IProcessor
{
	private ubyte id_;
	@property ubyte id() { return id_; }
	@property void id(ubyte n) { id_ = n; }

	mixin(VoxelContentQuick!("squareOne:voxel:processor:block", "", appName, dylanGrahamName));

	private Pool!(RenderData*) renderDataPool;
	private MeshBufferHost meshBufferHost;
	private DList!MeshResult uploadQueue;
	private Object uploadSyncObj;

	Resources resources;
	Moxane moxane;

	private enum mesherCount = 2;
	private int meshBarrel;
	private Mesher[] meshers;

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

		meshers.length = mesherCount;
		foreach(int x; 0 .. mesherCount) 
			meshers[x] = new Mesher(uploadSyncObj, &uploadQueue, this, resources, meshBufferHost);

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

	void meshChunk(MeshOrder mb)
	{
		synchronized(meshers[meshBarrel].meshSyncObj)
		{
			mb.chunk.meshBlocking(true, id_);
			meshers[meshBarrel].meshQueue.insert(mb);

			synchronized(meshers[meshBarrel].meshQueueMutex)
				meshers[meshBarrel].meshQueueWaiter.notify;
		}

		meshBarrel++;
		if(meshBarrel >= mesherCount) meshBarrel = 0;
	}

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

		while(uploadItemSw.peek().total!"msecs" < 4 && !isEmpty()){
			if(isEmpty) return;

			MeshResult upItem = getFromUploadQueue();
			IMeshableVoxelBuffer chunk = upItem.order.chunk;

			if(upItem.buffer is null)
			{
				removeChunk(upItem.order.chunk);
				continue;
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

			rd.vertexCount = upItem.buffer.vertexCount;

			/+rd.chunkMax = ChunkData.chunkDimensions * ChunkData.voxelScale;
			float invCM = 1f / rd.chunkMax;
			rd.fit10BitScale = 1023f * invCM;

			foreach(int i; 0 .. upItem.buffer.vertexCount) {
				Vector3f v = upItem.buffer.vertices[i];

				float vx = clamp(v.x, 0f, rd.chunkMax) * rd.fit10BitScale;
				uint vxU = cast(uint)vx & 1023;

				float vy = clamp(v.y, 0f, rd.chunkMax) * rd.fit10BitScale;
				uint vyU = cast(uint)vy & 1023;
				vyU <<= 10;

				float vz = clamp(v.z, 0f, rd.chunkMax) * rd.fit10BitScale;
				uint vzU = cast(uint)vz & 1023;
				vzU <<= 20;

				compressionBuffer[i] = vxU | vyU | vzU;
			}

			glBindBuffer(GL_ARRAY_BUFFER, rd.vertexBO);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, compressionBuffer.ptr, GL_STATIC_DRAW);

			//glBindBuffer(GL_ARRAY_BUFFER, rd.vertexBO);
			//glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * Vector3f.sizeof, upItem.buffer.vertices.ptr, GL_STATIC_DRAW);

			foreach(int i; 0 .. upItem.buffer.vertexCount) {
				Vector3f n = upItem.buffer.normals[i];

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

			glBindBuffer(GL_ARRAY_BUFFER, rd.normalBO);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, compressionBuffer.ptr, GL_STATIC_DRAW);+/

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

		uploadItemSw.stop();
		uploadItemSw.reset();
	}

	Renderer currentRenderer;
	void prepareRender(Renderer r)
	{
		import derelict.opengl3.gl3 : glBindVertexArray, glEnableVertexAttribArray, GL_TEXTURE0, glActiveTexture;

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
		//glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, null);
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
		import derelict.opengl3.gl3 : glDisableVertexAttribArray, glBindVertexArray;
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
}

private class Mesher
{
	private Object meshSyncObj;
	private DList!(MeshOrder) meshQueue;
	private Condition meshQueueWaiter;
	private Mutex meshQueueMutex;

	Object uploadSyncObj;
	DList!(BlockProcessor.MeshResult)* uploadQueue;

	BlockProcessor processor;
	Resources resources;
	MeshBufferHost host;

	bool busy;
	bool requiresRestart;

	double lowest, avg, highest;

	private Thread thread;

	this(Object uploadSyncObj, DList!(BlockProcessor.MeshResult)* uploadQueue, BlockProcessor processor, Resources resources, MeshBufferHost host)
	{
		meshSyncObj = new Object;
		meshQueueMutex = new Mutex;
		meshQueueWaiter = new Condition(meshQueueMutex);

		this.uploadSyncObj = uploadSyncObj;
		this.uploadQueue = uploadQueue;
		this.processor = processor;
		this.resources = resources;
		this.host = host;

		lowest = avg = highest = 0.0;

		thread = new Thread(&workerFuncRoot);
		thread.isDaemon = true;
		thread.name = BlockProcessor.stringof ~ " " ~ Mesher.stringof;
		thread.start;
	}

	void restart()
	{
		requiresRestart = false;
		thread.start;
	}

	private MeshOrder order;
	private IMeshableVoxelBuffer chunk;
	private MeshBuffer buffer;

	private void workerFuncRoot()
	{
		try workerFuncProper;
		catch(Throwable t)
		{
			import std.conv : to;
			Log log = processor.moxane.services.get!Log;
			log.write(Log.Severity.error, "Exception in thread " ~ thread.name ~ "\n\tMessage: " ~ to!string(t.message) ~ "\n\tLine: " ~ to!string(t.line) ~ "\n\tStacktrace: " ~ t.info.toString);
			log.write(Log.Severity.error, "Thread will be restarted...");

			if(chunk !is null)
			{
				chunk.meshBlocking(false, processor.id_);
				chunk.needsMesh = true;
			}
			chunk = null;

			if(buffer !is null)
			{
				buffer.reset;
				host.give(buffer);
			}
			buffer = null;

			order = MeshOrder();
			requiresRestart = true;
		}
	}

	private void workerFuncProper()
	{
		while(true)
		{
			busy = false;
			chunk = null;
			buffer = null;

			bool meshQueueEmpty = false;
			synchronized(meshSyncObj) meshQueueEmpty = meshQueue.empty;

			if(meshQueueEmpty)
				synchronized(meshQueueMutex)
					meshQueueWaiter.wait;
			synchronized(meshSyncObj)
			{
				order = meshQueue.front;
				chunk = order.chunk;
				meshQueue.removeFront;
			}

			if(chunk is null) continue;

			busy = true;
			do
				buffer = host.request(MeshSize.small);
			while(buffer is null);

			operateOnChunk;
		}
	}

	private void operateOnChunk()
	{
		void addVert(Vector3f vert, Vector3f normal, uint meta)
		{
			if(buffer.ms == MeshSize.small) 
			{
				if(buffer.vertexCount + 1 >= vertsSmall) 
				{
					MeshBuffer nbmb;
					while(nbmb is null)
						nbmb = host.request(MeshSize.medium);
					buffer.chunkMax = chunk.dimensionsProper * chunk.voxelScale;

					copyBuffer(buffer, nbmb);

					host.give(buffer);
					buffer = nbmb;
				}
			}
			else if(buffer.ms == MeshSize.medium) 
			{
				if(buffer.vertexCount + 1 >= vertsMedium) 
				{
					MeshBuffer nbmb;
					while(nbmb is null)
						nbmb = host.request(MeshSize.full);
					buffer.chunkMax = chunk.dimensionsProper * chunk.voxelScale;

					copyBuffer(buffer, nbmb);

					host.give(buffer);
					buffer = nbmb;
				}
			}
			else 
			{
				if(buffer.vertexCount + 1 >= vertsFull) 
				{
					string exp = "Chunk (" ~ "" ~ ") is too complex to mesh. Error: too many vertices for buffer.";
					throw new Exception(exp);
				}
			}

			import std.conv : to;
			if(buffer.vertexCount + 1 == vertsSmall) { processor.moxane.services.get!Log().write(Log.Severity.panic, "Requires more than " ~ to!string(vertsSmall) ~ " vertices."); }

			buffer.add(vert, normal, meta);
		}

		Vector3f[64] verts, normals;
		ushort[64] textureIDs;

		immutable int blkskp = chunk.blockskip;
		immutable int chunkDimLod = chunk.dimensionsProper * chunk.blockskip;

		buffer.chunkMax = chunkDimLod * chunk.voxelScale;

		for(int x = 0; x < chunkDimLod; x += blkskp) 
		{
			for(int y = 0; y < chunkDimLod; y += blkskp)  
			{
				for(int z = 0; z < chunkDimLod; z += blkskp)  
				{
					Voxel v = chunk.get(x, y, z);

					IBlockVoxelMesh bvm = cast(IBlockVoxelMesh)resources.getMesh(v.mesh);
					if(bvm is null) continue;

					Voxel[6] neighbours;
					SideSolidTable[6] isSidesSolid;

					neighbours[VoxelSide.nx] = chunk.get(x - blkskp, y, z);
					neighbours[VoxelSide.px] = chunk.get(x + blkskp, y, z);
					neighbours[VoxelSide.ny] = chunk.get(x, y - blkskp, z);
					neighbours[VoxelSide.py] = chunk.get(x, y + blkskp, z);
					neighbours[VoxelSide.nz] = chunk.get(x, y, z - blkskp);
					neighbours[VoxelSide.pz] = chunk.get(x, y, z + blkskp);

					isSidesSolid[VoxelSide.nx] = resources.getMesh(neighbours[VoxelSide.nx].mesh).isSideSolid(neighbours[VoxelSide.nx], VoxelSide.px);
					isSidesSolid[VoxelSide.px] = resources.getMesh(neighbours[VoxelSide.px].mesh).isSideSolid(neighbours[VoxelSide.px], VoxelSide.nx);
					isSidesSolid[VoxelSide.ny] = resources.getMesh(neighbours[VoxelSide.ny].mesh).isSideSolid(neighbours[VoxelSide.ny], VoxelSide.py);
					isSidesSolid[VoxelSide.py] = resources.getMesh(neighbours[VoxelSide.py].mesh).isSideSolid(neighbours[VoxelSide.py], VoxelSide.ny);
					isSidesSolid[VoxelSide.nz] = resources.getMesh(neighbours[VoxelSide.nz].mesh).isSideSolid(neighbours[VoxelSide.nz], VoxelSide.pz);
					isSidesSolid[VoxelSide.pz] = resources.getMesh(neighbours[VoxelSide.pz].mesh).isSideSolid(neighbours[VoxelSide.pz], VoxelSide.nz);

					int vertCount;
					bvm.generateMesh(v, chunk.blockskip, neighbours, isSidesSolid, Vector3i(x, y, z), verts, normals, vertCount);

					IBlockVoxelMaterial bvMat = cast(IBlockVoxelMaterial)resources.getMaterial(v.material);
					if(bvMat is null) continue;
					bvMat.generateTextureIDs(vertCount, verts, normals, textureIDs);

					foreach(int i; 0 .. vertCount)
						addVert(verts[i] * ChunkData.voxelScale, normals[i], textureIDs[i] & 2047);
				}
			}
		}

		synchronized(uploadSyncObj)
		{
			if(buffer.vertexCount == 0)
			{
				buffer.reset;
				host.give(buffer);
				buffer = null;
				chunk.meshBlocking(false, processor.id_);

				BlockProcessor.MeshResult mr;
				mr.order = order;
				mr.buffer = null;
				uploadQueue.insert(mr);
			}
			else
			{
				BlockProcessor.MeshResult mr;
				mr.order = order;
				mr.buffer = buffer;
				uploadQueue.insert(mr);
			}
		}

		buffer = null;
		chunk = null;
		order = MeshOrder.init;
	}
}

enum MeshSize {
	small,
	medium,
	full
}

enum int vertsSmall = 80_192;
enum int vertsSmallMemoryPerArr = vertsSmall * Vector3f.sizeof;

enum int vertsMedium = 24_576;
enum int vertsMediumMemoryPerArr = vertsMedium * Vector3f.sizeof;

enum int vertsFull = 147_456;
enum int vertsFullMemoryPerArr = vertsFull * Vector3f.sizeof;

private void copyBuffer(MeshBuffer smaller, MeshBuffer bigger) 
in {
	if(smaller.ms == MeshSize.small)
		assert(bigger.ms == MeshSize.medium || bigger.ms == MeshSize.full);
	if(smaller.ms == MeshSize.medium)
		assert(bigger.ms == MeshSize.full);
	assert(smaller.ms != MeshSize.full);
}
do {
	foreach(int v; 0 .. smaller.vertexCount)
		bigger.add(smaller.vertices[v], smaller.normals[v], smaller.meta[v]);
}

class MeshBuffer
{
	Vector3f[] vertices;
	Vector3f[] normals;
	uint[] meta;

	uint[] compressedVertices;
	uint[] compressedNormals;

	int vertexCount;

	const MeshSize ms;

	enum tenBitMax = 2 ^^ 10 - 1;
	private float chunkMax_ = 0f;
	@property float chunkMax() const { return chunkMax_; }
	@property void chunkMax(float cm)
	{
		chunkMax_ = cm;
		inv = 1f / cm;
		fit10Bit = tenBitMax * inv;
	}
	float inv = 0f, fit10Bit = 0f;

	this(MeshSize ms) 
	{
		this.ms = ms;

		if(ms == MeshSize.small) 
		{
			vertices.length = vertsSmall;
			normals.length = vertsSmall;
			meta.length = vertsSmall;
			compressedVertices.length = vertsSmall;
			compressedNormals.length = vertsSmall;
		}
		if(ms == MeshSize.medium) 
		{
			vertices.length = vertsMedium;
			normals.length = vertsMedium;
			meta.length = vertsMedium;
			compressedVertices.length = vertsMedium;
			compressedNormals.length = vertsMedium;
		}
		if(ms == MeshSize.full) 
		{
			vertices.length = vertsFull;
			normals.length = vertsFull;
			meta.length = vertsFull;
			compressedVertices.length = vertsFull;
			compressedNormals.length = vertsFull;
		}
	}

	void add(Vector3f vert, Vector3f normal, uint meta) 
	{
		vertices[vertexCount] = vert;
		normals[vertexCount] = normal;
		this.meta[vertexCount] = meta;

		const float vx = clamp(vert.x, 0f, chunkMax_) * fit10Bit;
		uint vxU = cast(uint)vx & tenBitMax;

		const float vy = clamp(vert.y, 0f, chunkMax_) * fit10Bit;
		uint vyU = cast(uint)vy & tenBitMax;
		vyU <<= 10;

		const float vz = clamp(vert.z, 0f, chunkMax_) * fit10Bit;
		uint vzU = cast(uint)vz & tenBitMax;
		vzU <<= 20;

		compressedVertices[vertexCount] = vxU | vyU | vzU;

		const float nx = (((clamp(normal.x, -1f, 1f) + 1f) * 0.5f) * tenBitMax);
		const float ny = (((clamp(normal.y, -1f, 1f) + 1f) * 0.5f) * tenBitMax);
		const float nz = (((clamp(normal.z, -1f, 1f) + 1f) * 0.5f) * tenBitMax);

		const uint nxU = (cast(uint)nx & tenBitMax);
		const uint nyU = (cast(uint)ny & tenBitMax) << 10;
		const uint nzU = (cast(uint)nz & tenBitMax) << 20;

		compressedNormals[vertexCount] = nxU | nyU | nzU;

		vertexCount++;
	}

	void reset() 
	{ vertexCount = 0; }
}

private class MeshBufferHost
{
	enum int smallMeshCount = 20;
	enum int mediumMeshCount = 0;
	enum int fullMeshCount = 0;

	private DList!(MeshBuffer) smallMeshes;
	private DList!(MeshBuffer) mediumMeshes;
	private DList!(MeshBuffer) fullMeshes;

	this() 
	{
		foreach(int x; 0 .. smallMeshCount) 
			smallMeshes.insertBack(new MeshBuffer(MeshSize.small));
		foreach(int x; 0 .. mediumMeshCount)
			mediumMeshes.insertBack(new MeshBuffer(MeshSize.medium));
		foreach(int x; 0 .. fullMeshCount)
			fullMeshes.insertBack(new MeshBuffer(MeshSize.full));
	}

	MeshBuffer request(MeshSize m) 
	{
		synchronized(this) 
		{
			if(m == MeshSize.small) 
			{
				if(!smallMeshes.empty) 
				{
					auto bmb = smallMeshes.back;
					smallMeshes.removeBack();
					return bmb;
				}
			}
			if(m == MeshSize.medium) 
			{
				if(!mediumMeshes.empty) 
				{
					auto bmb = mediumMeshes.back;
					mediumMeshes.removeBack();
					return bmb;
				}
			}
			if(m == MeshSize.full) 
			{
				if(!fullMeshes.empty) 
				{
					auto bmb = fullMeshes.back;
					fullMeshes.removeBack();
					return bmb;
				}
			}

			return null;
		}
	}

	void give(MeshBuffer bmb) 
	{
		synchronized(this) 
		{
			bmb.reset();

			if(bmb.ms == MeshSize.small)
				smallMeshes.insertBack(bmb);
			if(bmb.ms == MeshSize.medium) 
				mediumMeshes.insertBack(bmb);
			if(bmb.ms == MeshSize.full) 
				fullMeshes.insertBack(bmb);
		}
	}
}