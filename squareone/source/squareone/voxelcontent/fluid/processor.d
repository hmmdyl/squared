module squareone.voxelcontent.fluid.processor;

import squareone.voxel;
import squareone.util.spec;

import moxane.core;
import moxane.graphics.renderer;
import moxane.utils.pool;
import moxane.graphics.effect;
import moxane.graphics.log;
import moxane.utils.maybe;

import core.thread : Thread;
import dlib.math.matrix;
import dlib.math.vector;
import dlib.math.transformation;
import dlib.math.utils : clamp;
import std.random;
import std.algorithm;
import std.datetime.stopwatch;

final class FluidProcessor : IProcessor
{
	private ubyte id_;
	@property ubyte id() { return id_; }
	@property void id(ubyte n) { id_ = n; }

	mixin(VoxelContentQuick!("squareOne:voxel:processor:fluid", "", appName, dylanGrahamName));

	Moxane moxane;
	Resources resources;

	private Pool!(RenderData*) renderDataPool;
	private Pool!(MeshBuffer) meshBufferPool;
	private Channel!MeshResult meshResults;
	private enum mesherCount = 1;
	private size_t meshBarrel;
	private Mesher[] meshers;

	FluidMesh fluidMesh;

	private uint vao;
	private Effect effect;

	private float fluidTime = 1f;
	private float[8] waveAmplitudes;
	private float[8] waveWavelengths;
	private float[8] waveSpeeds;
	private Vector2f[8] waveDirections;
	float fresnelReflectiveFactor;
	float murkDepth;
	float minimumMurkStrength, maximumMurkStrength;
	Vector3f waterColour;

	private IVoxelMesh[] meshOn;

	this(Moxane moxane, IVoxelMesh[] meshOn)
	in(moxane !is null) in(meshOn !is null)
	do {
		this.moxane = moxane;
		meshResults = new Channel!MeshResult;
		meshBufferPool = Pool!(MeshBuffer)(() => new MeshBuffer(), 24, false);
		renderDataPool = Pool!(RenderData*)(() => new RenderData(), 64);
		this.meshOn = meshOn;
	}

	void finaliseResources(Resources res)
	{
		assert(res !is null);
		resources = res;

		fluidMesh = cast(FluidMesh)res.getMesh(FluidMesh.technicalStatic);

		meshers = new Mesher[](mesherCount);
		foreach(x; 0 .. mesherCount)
			meshers[x] = new Mesher(this, &meshBufferPool, meshResults, fluidMesh.id_);

		import std.file : readText;
		import derelict.opengl3.gl3 : GL_VERTEX_SHADER, GL_FRAGMENT_SHADER, glGenVertexArrays;

		glGenVertexArrays(1, &vao);
		Log log = moxane.services.getAOrB!(GraphicsLog, Log);
		Shader vs = new Shader, fs = new Shader;
		vs.compile(readText(AssetManager.translateToAbsoluteDir("content/shaders/fluidProcessor.vs.glsl")), GL_VERTEX_SHADER, log);
		fs.compile(readText(AssetManager.translateToAbsoluteDir("content/shaders/fluidProcessor.fs.glsl")), GL_FRAGMENT_SHADER, log);
		effect = new Effect(moxane, FluidProcessor.stringof);
		effect.attachAndLink(vs, fs);
		effect.bind;
		effect.findUniform("ModelViewProjection");
		effect.findUniform("ModelView");
		effect.findUniform("Fit10bScale");
		effect.findUniform("Model");
		effect.findUniform("Time");
		effect.findUniform("Amplitudes");
		effect.findUniform("Wavelengths");
		effect.findUniform("Speed");
		effect.findUniform("Direction");
		effect.findUniform("RefractionDiffuse");
		effect.findUniform("RefractionNormal");
		effect.findUniform("RefractionWorldPos");
		effect.findUniform("RefractionDepth");
		effect.findUniform("CameraPosition");
		effect.findUniform("NearPlane");
		effect.findUniform("FarPlane");
		effect.findUniform("FresnelReflectiveFactor");
		effect.findUniform("MurkDepth");
		effect.findUniform("MinimumMurkStrength");
		effect.findUniform("MaximumMurkStrength");
		effect.findUniform("DebugColour");
		effect.unbind;

		fresnelReflectiveFactor = 0.9f;
		murkDepth = 1.751f;
		minimumMurkStrength = 0.447f;
		maximumMurkStrength = 0.634f;
		//waterColour = Vector3f(0.1f, 0.75f, 0.9f);
		waterColour = Vector3f(54f / 255f, 0f, 1f);

		/*foreach(ref float amplitude; waveAmplitudes)
			amplitude = uniform01!float() * 0.075f;
		foreach(ref float wavelength; waveWavelengths)
			wavelength = uniform01!float() * 10f;
		foreach(ref float speed; waveSpeeds)
			speed = uniform01!float() * 0.5f;
		foreach(ref Vector2f direction; waveDirections)
			direction = Vector2f(((uniform01!float() - 0.5f) * 2f), ((uniform01!float() - 0.5f) * 2f));*/
	
		waveAmplitudes[] = 0f;
		waveWavelengths[] = 0f;
		waveSpeeds[] = 0f;
		waveDirections[] = Vector2f(0f, 0f);

		waveAmplitudes[0] = 0.5f;
		waveWavelengths[0] = 3f;
		waveSpeeds[0] = 0.25f;
		waveDirections[0] = Vector2f(1f, 0f);

		waveAmplitudes[1] = 0.04f;
		waveWavelengths[1] = 2f;
		waveSpeeds[1] = 0.2f;
		waveDirections[1] = Vector2f(0.1f, 9f);

		waveAmplitudes[2] = 0.025f;
		waveWavelengths[2] = 0.5f;
		waveSpeeds[2] = 0.35f;
		waveDirections[2] = Vector2f(0.9f, 0.4f);
	}

	~this()
	{
		import derelict.opengl3.gl3 : glDeleteVertexArrays;
		glDeleteVertexArrays(1, &vao);

		foreach(x; 0 .. meshers.length)
		{
			Mesher m = meshers[x];
			destroy(m);
			meshers[x] = null;
		}
	}

	void meshChunk(MeshOrder c)
	{
		c.chunk.meshBlocking(true, id_);
		meshers[meshBarrel].orders.send(c);
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

	void updateFromManager()
	{ }

	private uint[] compressionBuffer = new uint[](MeshBuffer.elements);
	private void performUploads()
	{
		import derelict.opengl3.gl3;

		StopWatch uploadSw = StopWatch(AutoStart.yes);

		while(uploadSw.peek.total!"msecs" < 4 && !meshResults.empty)
		{
			Maybe!MeshResult meshResult = meshResults.tryGet;
			if(meshResult.isNull) return;

			MeshResult result = *meshResult.unwrap;

			if(result.buffer is null)
			{
				if(!isRdNull(result.order.chunk))
					removeChunk(result.order.chunk);
				result.order.chunk.meshBlocking(false, id_);
				continue;
			}

			bool hasRd = !isRdNull(result.order.chunk);
			RenderData* rd;
			if(hasRd)
				rd = getRd(result.order.chunk);
			else
			{
				rd = renderDataPool.get;
				rd.create;
				result.order.chunk.renderData[id_] = cast(void*)rd;
			}

			rd.vertexCount = result.buffer.vertexCount;
			rd.chunkMax = result.order.chunk.dimensionsProper * result.order.chunk.blockskip * result.order.chunk.voxelScale;
			const float invCM = 1f / rd.chunkMax;
			rd.fit10BitScale = 1023f * invCM;

			glBindBuffer(GL_ARRAY_BUFFER, rd.vertex);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * Vector3f.sizeof, result.buffer.vertices.ptr, GL_STATIC_DRAW);

			foreach(int i; 0 .. result.buffer.vertexCount) {
				Vector3f n = result.buffer.normals[i];

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

			glBindBuffer(GL_ARRAY_BUFFER, rd.normal);
			glBufferData(GL_ARRAY_BUFFER, rd.vertexCount * uint.sizeof, compressionBuffer.ptr, GL_STATIC_DRAW);

			result.order.chunk.meshBlocking(false, id_);
			result.buffer.reset;
			meshBufferPool.give(result.buffer);
		}
	}

	Renderer renderer;
	void prepareRender(Renderer renderer)
	{
		this.renderer = renderer;
		import derelict.opengl3.gl3;

		performUploads;
		glBindVertexArray(vao);

		foreach(x; 0 .. 2)
			glEnableVertexAttribArray(x);

		effect.bind;

		fluidTime += moxane.deltaTime;
		effect["Time"].set(fluidTime);
		effect["Amplitudes"].set(waveAmplitudes.ptr, 8);
		effect["Wavelengths"].set(waveWavelengths.ptr, 8);
		effect["Speed"].set(waveSpeeds.ptr, 8);
		effect["Direction"].set(waveDirections.ptr, 8);


		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, renderer.sceneDup.diffuse);
		glActiveTexture(GL_TEXTURE1);
		glBindTexture(GL_TEXTURE_2D, renderer.sceneDup.normal);
		glActiveTexture(GL_TEXTURE2);
		glBindTexture(GL_TEXTURE_2D, renderer.sceneDup.worldPos);
		glActiveTexture(GL_TEXTURE3);
		glBindTexture(GL_TEXTURE_2D, renderer.sceneDup.depthTexture.depth);

		effect["RefractionDiffuse"].set(0);
		effect["RefractionNormal"].set(1);
		effect["RefractionWorldPos"].set(2);
		effect["RefractionDepth"].set(3);

		effect["CameraPosition"].set(renderer.primaryCamera.position);
		effect["NearPlane"].set(renderer.primaryCamera.perspective.near);
		effect["FarPlane"].set(renderer.primaryCamera.perspective.far);
	
		effect["FresnelReflectiveFactor"].set(fresnelReflectiveFactor);
		effect["MurkDepth"].set(murkDepth);
		effect["MinimumMurkStrength"].set(minimumMurkStrength);
		effect["MaximumMurkStrength"].set(maximumMurkStrength);
		effect["DebugColour"].set(waterColour);
	}

	void render(IMeshableVoxelBuffer chunk, ref LocalContext lc, ref uint drawCalls, ref uint numVerts)
	{
		if(lc.type != PassType.waterRefraction) return;

		RenderData* rd = getRd(chunk);
		if(rd is null) return;

		Matrix4f m = translationMatrix(chunk.transform.position);
		Matrix4f nm = lc.model * m;
		Matrix4f mvp = lc.projection * lc.view * nm;
		Matrix4f mv = lc.view * nm;

		effect["ModelViewProjection"].set(&mvp);
		effect["ModelView"].set(&mv);
		effect["Fit10bScale"].set(rd.fit10BitScale);
		effect["Model"].set(&nm);

		import derelict.opengl3.gl3;
		glBindBuffer(GL_ARRAY_BUFFER, rd.vertex);
		glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, rd.normal);
		glVertexAttribPointer(1, 4, GL_UNSIGNED_INT_2_10_10_10_REV, false, 0, null);
		
		glDrawArrays(GL_TRIANGLES, 0, rd.vertexCount);
		numVerts += rd.vertexCount;
		drawCalls++;
	}

	void endRender()
	{
		import derelict.opengl3.gl3;

		glActiveTexture(GL_TEXTURE3);
		glBindTexture(GL_TEXTURE_2D, 0);
		glActiveTexture(GL_TEXTURE2);
		glBindTexture(GL_TEXTURE_2D, 0);
		glActiveTexture(GL_TEXTURE1);
		glBindTexture(GL_TEXTURE_2D, 0);
		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, 0);

		foreach(x; 0 .. 2)
			glDisableVertexAttribArray(x);

		effect.unbind;

		glBindVertexArray(0);
	}
}

struct RenderData
{
	uint vertex, normal;
	float chunkMax, fit10BitScale;
	int vertexCount;

	void create()
	{
		import derelict.opengl3.gl3 : glGenBuffers;
		glGenBuffers(1, &vertex);
		glGenBuffers(1, &normal);
		vertexCount = 0;
	}

	void destroy()
	{
		import derelict.opengl3.gl3 : glDeleteBuffers;
		glDeleteBuffers(1, &vertex);
		glDeleteBuffers(1, &normal);
		vertexCount = 0;
	}
}

final class FluidMesh : IVoxelMesh
{
	private ushort id_;
	@property ushort id() { return id_; }
	@property void id(ushort n) { id_ = n; }

	static immutable string technicalStatic = "squareOne:voxel:fluidMesh";
	mixin(VoxelContentQuick!(technicalStatic, "Fluid", appName, dylanGrahamName));

	SideSolidTable isSideSolid(Voxel voxel, VoxelSide side) { return SideSolidTable.notSolid; }
}

private struct MeshResult
{
	MeshOrder order;
	MeshBuffer buffer;
}

private immutable Vector3f[8] cubeVertices = [
	Vector3f(0, 0, 0), // ind0
	Vector3f(1, 0, 0), // ind1
	Vector3f(0, 0, 1), // ind2
	Vector3f(1, 0, 1), // ind3
	Vector3f(0, 1, 0), // ind4
	Vector3f(1, 1, 0), // ind5
	Vector3f(0, 1, 1), // ind6
	Vector3f(1, 1, 1)  // ind7
];

private immutable ushort[3][2][6] cubeIndices = [
	[[0, 2, 6], [6, 4, 0]], // -X
	[[7, 3, 1], [1, 5, 7]], // +X
	[[0, 1, 3], [3, 2, 0]], // -Y
	[[7, 5, 4], [4, 6, 7]], // +Y
	[[5, 1, 0], [0, 4, 5]], // -Z
	[[2, 3, 7], [7, 6, 2]]  // +Z
];

private immutable Vector3f[6] cubeNormals = [
	Vector3f(-1, 0, 0),
	Vector3f(1, 0, 0),
	Vector3f(0, -1, 0),
	Vector3f(0, 1, 0),
	Vector3f(0, 0, -1),
	Vector3f(0, 0, 1)
];

private class Mesher
{
	FluidProcessor processor;
	Pool!(MeshBuffer)* meshBufferPool;
	Channel!MeshResult results;
	ushort fluidID;

	ushort[] meshOn;

	Channel!MeshOrder orders;
	private bool terminate;

	private Thread thread;

	this(FluidProcessor processor, Pool!(MeshBuffer)* meshBufferPool, Channel!MeshResult results, ushort fluidID)
	in(processor !is null)
	in(meshBufferPool !is null)
	in(results !is null)
	do {
		this.processor = processor;
		this.meshBufferPool = meshBufferPool;
		this.results = results;
		this.fluidID = fluidID;
		orders = new Channel!MeshOrder;
		foreach(IVoxelMesh mesh; processor.meshOn)
			meshOn ~= mesh.id;

		thread = new Thread(&worker);
		thread.name = FluidProcessor.stringof ~ " " ~ Mesher.stringof;
		thread.isDaemon = true;
		thread.start;
	}

	~this()
	{
		if(thread !is null && thread.isRunning)
		{
			terminate = true;
			orders.notifyUnsafe;
			thread.join;
		}
	}

	private void worker()
	{
		try
		{
			while(!terminate)
			{
				Maybe!MeshOrder order = orders.await;
				if(!order.isNull)
					execute(*order.unwrap);
				else return;
			}
		}
		catch(Throwable t)
		{
			import std.conv : to;
			Log log = processor.moxane.services.get!Log;
			log.write(Log.Severity.error, "Exception in " ~ thread.name ~ "\n\tMessage: " ~ to!string(t.message) ~ "\n\tLine: " ~ to!string(t.line) ~ "\n\tStacktrace: " ~ t.info.toString);
			log.write(Log.Severity.error, "Thread will not be restarted.");
		}
	}

	private void execute(MeshOrder o)
	{
		IMeshableVoxelBuffer c = o.chunk;
		immutable int blockskip = c.blockskip;

		MeshBuffer buffer;
		do buffer = meshBufferPool.get;
		while(buffer is null);

		immutable int chunkDimLod = c.dimensionsProper * c.blockskip;

		for(int x = 0; x < chunkDimLod; x += blockskip)
		for(int y = 0; y < chunkDimLod; y += blockskip)
		for(int z = 0; z < chunkDimLod; z += blockskip)
		{
			Voxel v = c.get(x, y, z);
			Voxel[6] neighbours;
			Voxel[4] diagNeighbours, diagNeighboursUpper;

			neighbours[VoxelSide.nx] = c.get(x - blockskip, y, z);
			neighbours[VoxelSide.px] = c.get(x + blockskip, y, z);
			neighbours[VoxelSide.ny] = c.get(x, y - blockskip, z);
			neighbours[VoxelSide.py] = c.get(x, y + blockskip, z);
			neighbours[VoxelSide.nz] = c.get(x, y, z - blockskip); // caaused crash, related to glass
			neighbours[VoxelSide.pz] = c.get(x, y, z + blockskip);

			diagNeighbours[0] = c.get(x - blockskip, y, z - blockskip);
			diagNeighbours[1] = c.get(x - blockskip, y, z + blockskip);
			diagNeighbours[2] = c.get(x + blockskip, y, z - blockskip);
			diagNeighbours[3] = c.get(x + blockskip, y, z + blockskip);

			diagNeighboursUpper[0] = c.get(x - blockskip, y + blockskip, z - blockskip);
			diagNeighboursUpper[1] = c.get(x - blockskip, y + blockskip, z + blockskip);
			diagNeighboursUpper[2] = c.get(x + blockskip, y + blockskip, z - blockskip);
			diagNeighboursUpper[3] = c.get(x + blockskip, y + blockskip, z + blockskip);

			void addVoxel(bool isOverrun)
			{
				SideSolidTable[6] isSideSolid;
				Vector3f vbias = Vector3f(x, y, z);

				SideSolidTable doMeshSide(int side)
				{
					if(isOverrun)
					{
						if(side == VoxelSide.py) return SideSolidTable.notSolid;
						else return SideSolidTable.solid;
					}

					foreach(m; meshOn)
						if(neighbours[side].mesh == m)
							return SideSolidTable.notSolid;
					return SideSolidTable.solid;
				}

				isSideSolid[VoxelSide.nx] = neighbours[VoxelSide.nx].mesh == fluidID ? SideSolidTable.solid : doMeshSide(VoxelSide.nx); //: processor.resources.getMesh(neighbours[VoxelSide.nx].mesh).isSideSolid(neighbours[VoxelSide.nx], VoxelSide.px);
				isSideSolid[VoxelSide.px] = neighbours[VoxelSide.px].mesh == fluidID ? SideSolidTable.solid : doMeshSide(VoxelSide.px);//: processor.resources.getMesh(neighbours[VoxelSide.px].mesh).isSideSolid(neighbours[VoxelSide.px], VoxelSide.nx);
				isSideSolid[VoxelSide.ny] = neighbours[VoxelSide.ny].mesh == fluidID ? SideSolidTable.solid : doMeshSide(VoxelSide.ny);//: processor.resources.getMesh(neighbours[VoxelSide.ny].mesh).isSideSolid(neighbours[VoxelSide.ny], VoxelSide.py);
				isSideSolid[VoxelSide.py] = neighbours[VoxelSide.py].mesh == fluidID ? SideSolidTable.solid : doMeshSide(VoxelSide.py);//: processor.resources.getMesh(neighbours[VoxelSide.py].mesh).isSideSolid(neighbours[VoxelSide.py], VoxelSide.ny);
				isSideSolid[VoxelSide.nz] = neighbours[VoxelSide.nz].mesh == fluidID ? SideSolidTable.solid : doMeshSide(VoxelSide.nz);//: processor.resources.getMesh(neighbours[VoxelSide.nz].mesh).isSideSolid(neighbours[VoxelSide.nz], VoxelSide.pz);
				isSideSolid[VoxelSide.pz] = neighbours[VoxelSide.pz].mesh == fluidID ? SideSolidTable.solid : doMeshSide(VoxelSide.pz);//: processor.resources.getMesh(neighbours[VoxelSide.pz].mesh).isSideSolid(neighbours[VoxelSide.pz], VoxelSide.nz);

				void addTriangle(ushort[3] indices, int dir)
				{
					buffer.add((cubeVertices[indices[0]] * blockskip + vbias) * c.voxelScale, cubeNormals[dir], [0,0,0,0]);
					buffer.add((cubeVertices[indices[1]] * blockskip + vbias) * c.voxelScale, cubeNormals[dir], [0,0,0,0]);
					buffer.add((cubeVertices[indices[2]] * blockskip + vbias) * c.voxelScale, cubeNormals[dir], [0,0,0,0]);
				}
				void addSide(int dir)
				{
					addTriangle(cubeIndices[dir][0], dir);
					addTriangle(cubeIndices[dir][1], dir);
				}

				if(isSideSolid[VoxelSide.nx] != SideSolidTable.solid) addSide(VoxelSide.nx);
				if(isSideSolid[VoxelSide.px] != SideSolidTable.solid) addSide(VoxelSide.px);
				if(isSideSolid[VoxelSide.ny] != SideSolidTable.solid) addSide(VoxelSide.ny);
				if(isSideSolid[VoxelSide.py] != SideSolidTable.solid) addSide(VoxelSide.py);
				if(isSideSolid[VoxelSide.nz] != SideSolidTable.solid) addSide(VoxelSide.nz);
				if(isSideSolid[VoxelSide.pz] != SideSolidTable.solid) addSide(VoxelSide.pz);
			}

			//if(v.mesh != fluidID) continue;

			if(v.mesh == fluidID)
				addVoxel(false);
			if(v.mesh != fluidID && v.mesh != 0)
			{
				if(any!((Voxel v) => v.mesh == fluidID)(neighbours[]))
					addVoxel(true);
				if(count!((Voxel v) => v.mesh == fluidID)(diagNeighbours[]) > 0 && count!((Voxel v) => v.mesh == fluidID)(diagNeighboursUpper[]) == 0)
					addVoxel(true);
			}
			/+if(v.mesh != fluidID && v.mesh != 0 && 
			   (any!((Voxel v) => v.mesh == fluidID)(neighbours[]) || 
				(count!((Voxel v) => v.mesh == fluidID)(diagNeighbours[]) > 1)))
				addVoxel(true);+/
		}

		if(buffer.vertexCount == 0)
		{
			buffer.reset;
			meshBufferPool.give(buffer);
			buffer = null;
			//c.meshBlocking(false, processor.id_);

			MeshResult mr;
			mr.order = o;
			mr.buffer = null;
			results.send(mr);
		}
		else
		{
			MeshResult mr;
			mr.order = o;
			mr.buffer = buffer;
			results.send(mr);
		}
	}
}

private class MeshBuffer
{
	enum elements = 80192;

	Vector3f[] vertices;
	Vector3f[] normals;
	ubyte[] colours;
	int vertexCount;

	this()
	{
		vertices = new Vector3f[](elements);
		normals = new Vector3f[](elements);
		colours = new ubyte[](elements*4);
	}

	void add(Vector3f vertex, Vector3f normal, ubyte[4] colour)
	{
		vertices[vertexCount] = vertex;
		normals[vertexCount] = normal;
		colours[vertexCount * 4 .. vertexCount * 4 + 4] = colour[];
		vertexCount++;
	}

	void reset() { vertexCount = 0; }
}

import cimgui;
import moxane.graphics.imgui;

final class FluidProcessorDebugAttachment : IImguiRenderable
{
	FluidProcessor processor;

	this(FluidProcessor processor)
	in(processor !is null)
	{this.processor = processor;}

	void renderUI(ImguiRenderer r, Renderer rr, ref LocalContext lc)
	{
		igBegin("Fluid Processor");
		scope(exit) igEnd();

		igSliderFloat("Fresnel reflectivity", &processor.fresnelReflectiveFactor, 0, 3);
		igSliderFloat("Murk depth", &processor.murkDepth, 0.25f, 20f);
		igSliderFloat("Min murk strength", &processor.minimumMurkStrength, 0f, 1f);
		igSliderFloat("Max murk strength", &processor.maximumMurkStrength, 0f, 1f);
	
		//float[3] colour = [processor.waterColour.x / 255f, processor.waterColour.y / 255f, processor.waterColour.z / 255f];
		igColorPicker3("Water colour", processor.waterColour.arrayof);
		//processor.waterColour.x = colour[0] / 255f;
		//processor.waterColour.y = colour[1] / 255f;
		//processor.waterColour.z = colour[2] / 255f;
	}
}