module squareone.systems.sky;

import squareone.systems.gametime;
import moxane.core;
import moxane.graphics.renderer;
import moxane.graphics.assimp;
import moxane.graphics.effect;
import moxane.graphics.texture;
import moxane.graphics.transformation;
import moxane.graphics.imgui;
import moxane.network.semantic;

import std.algorithm.searching : canFind;
import derelict.opengl3.gl3;
import containers.unrolledlist;
import dlib.math.vector : Vector3f;
import dlib.math.matrix : Matrix4f;
import dlib.math.transformation;
import std.experimental.allocator.gc_allocator;
import std.file : readText;
import cimgui;

class SkySystem
{
	Entity skyBox;

	this(Moxane moxane)
	{
		EntityManager em = moxane.services.get!EntityManager;
		em.onEntityAdd.addCallback(&entityAddCallback);
		em.onEntityRemove.addCallback(&entityRemoveCallback);
	}

	private void entityAddCallback(ref OnEntityAdd e) @safe
	{
		if(e.entity.has!SkyComponent && e.entity.has!Transform)
		{
			synchronized(this)
			{
				if(skyBox is null)
					skyBox = e.entity;
				else throw new Exception("Error! Only one skybox entity is permitted at a time");
			}
		}
	}

	private void entityRemoveCallback(ref OnEntityAdd e) @trusted
	{
		if(skyBox == e.entity)
			synchronized(this)
				if(skyBox == e.entity)
					skyBox = null;
	}
}

alias SkyRenderer7R24D = SkyRenderer!(7, 24);

class SkyRenderer(int Rings, int TimeDivisions) : IRenderable
{
	SkySystem skySystem;

	private uint vao;
	private uint vertexBO;
	private uint vertexCount;

	private Effect skyEffect;
	private Texture2D colourMap;

	private ubyte[4][TimeDivisions][Rings] colours;

	this(Moxane moxane, SkySystem skySystem)
	in(moxane !is null)
	in(skySystem !is null)
	{
		this.skySystem = skySystem;

		glGenVertexArrays(1, &vao);

		Vector3f[] verts;
		loadMesh!(Vector3f, GCAllocator)(AssetManager.translateToAbsoluteDir("content/models/skySphere.dae"), verts);
		scope(exit) GCAllocator.instance.deallocate(verts);

		vertexCount = cast(uint)verts.length;

		glGenBuffers(1, &vertexBO);
		glBindBuffer(GL_ARRAY_BUFFER, vertexBO);
		scope(exit) glBindBuffer(GL_ARRAY_BUFFER, 0);

		glBufferData(GL_ARRAY_BUFFER, verts.length * Vector3f.sizeof, verts.ptr, GL_STATIC_DRAW);

		foreach(d; 0 .. TimeDivisions)
			foreach(r; 0 .. Rings)
				colours[r][d] = [0, 0, 0, 255];

		colourMap = new Texture2D(colours.ptr, TimeDivisions, Rings, Filter.linear, Filter.linear, false, true);

		Log log = moxane.services.get!Log;
		Shader vs = new Shader, fs = new Shader;
		vs.compile(readText(AssetManager.translateToAbsoluteDir("content/shaders/sky.vs.glsl")), GL_VERTEX_SHADER, log);
		fs.compile(readText(AssetManager.translateToAbsoluteDir("content/shaders/sky.fs.glsl")), GL_FRAGMENT_SHADER, log);
		skyEffect = new Effect(moxane, SkyRenderer.stringof);
		skyEffect.attachAndLink(vs, fs);
		skyEffect.bind;
		skyEffect.findUniform("MVP");
		skyEffect.findUniform("Model");
		skyEffect.findUniform("ColourMap");
		skyEffect.findUniform("Time");
		skyEffect.unbind;
	}

	~this()
	{
		glDeleteVertexArrays(1, &vao);
	}

	void render(Renderer renderer, ref LocalContext lc, out uint drawCalls, out uint numVerts)
	{
		if(skySystem.skyBox is null) return;

		synchronized(skySystem)
		{
			glBindVertexArray(vao);
			scope(exit) glBindVertexArray(0);

			SkyComponent* sky = skySystem.skyBox.get!SkyComponent;
			if(sky is null) return;
			Transform* transform = skySystem.skyBox.get!Transform;
			if(transform is null) return;

			glBindVertexArray(vao);
			scope(exit) glBindVertexArray(0);
			glEnableVertexAttribArray(0);
			scope(exit) glDisableVertexAttribArray(0);

			skyEffect.bind;
			scope(exit) skyEffect.unbind;
			glActiveTexture(GL_TEXTURE0);
			colourMap.bind;
			scope(exit) colourMap.unbind;
			skyEffect["ColourMap"].set(0);

			Matrix4f m = lc.model * scaleMatrix(Vector3f(sky.horizScale, sky.vertScale, sky.horizScale)) * transform.matrix;
			Matrix4f mvp = lc.projection * lc.view * m;

			skyEffect["Model"].set(&m);
			skyEffect["MVP"].set(&mvp);

			skyEffect["Time"].set((sky.time.decimal + 0.5f) / VirtualTime.maxHour);

			glBindBuffer(GL_ARRAY_BUFFER, vertexBO);
			glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, null);
			scope(exit) glBindBuffer(GL_ARRAY_BUFFER, 0);

			glDrawArrays(GL_TRIANGLES, 0, vertexCount);

			drawCalls += 1;
			numVerts += 1;
		}
	}

	ubyte[] exportColourMap()
	{
		import cerealed;
		return cerealize(colours);
	}

	void importColourMap(ubyte[] bytes)
	{
		import cerealed;
		colours = decerealize!(ubyte[4][TimeDivisions][Rings])(bytes);
	}

	static final class DebugAttachment : IImguiRenderable
	{
		SkyRenderer!(Rings, TimeDivisions) skyRenderer;
		Moxane moxane;

		this(SkyRenderer!(Rings, TimeDivisions) sky, Moxane moxane) { this.skyRenderer = sky; this.moxane = moxane; }

		private int timeSlider;
		private int ringSlider;

		void renderUI(ImguiRenderer imgui, Renderer renderer, ref LocalContext lc)
		{
			igBegin("Sky");
			scope(exit) igEnd();

			if(igButton("Import"))
			{
				string dir = AssetManager.translateToAbsoluteDir("skyColourMap.txt");
				import std.file;
				if(exists(dir))
				{
					Log log = moxane.services.get!Log;
					log.write(Log.Severity.info, "Loading SkyRenderer colour map...");
					scope(success) log.write(Log.Severity.info, "Loaded");
					ubyte[] bytes = cast(ubyte[])read(dir);
					skyRenderer.importColourMap(bytes);
				}
			}
			igSameLine();
			if(igButton("Export"))
			{
				string dir = AssetManager.translateToAbsoluteDir("skyColourMap.txt");
				import std.file;
				ubyte[] bytes = skyRenderer.exportColourMap;
				write(dir, bytes);
			}

			igSliderInt("Time", &timeSlider, 0, TimeDivisions - 1);
			auto prevIdx = timeSlider - 1;
			if(prevIdx < 0) prevIdx = TimeDivisions - 1;
			auto currIdx = timeSlider;
			auto nextIdx = timeSlider + 1;
			if(nextIdx >= TimeDivisions) nextIdx = 0;

			ubyte[4][Rings] prev, curr, next;
			foreach(ring; 0 .. Rings)
			{
				prev[ring] = skyRenderer.colours[ring][prevIdx];
				curr[ring] = skyRenderer.colours[ring][currIdx];
				next[ring] = skyRenderer.colours[ring][nextIdx];
			}
				
			igText("Ring: Prev  |  Curr  |  Next");
			foreach(ring; 0 .. Rings)
			{
				igText("%d: %d %d %d  |  %d %d %d  |  %d %d %d", ring, prev[ring][2], prev[ring][1], prev[ring][0], curr[ring][2], curr[ring][1], curr[ring][0], next[ring][2], next[ring][1], next[ring][0]);
			}

			igSliderInt("Ring", &ringSlider, 0, Rings - 1);
			float[3] col = [skyRenderer.colours[ringSlider][timeSlider][2] / 255f, skyRenderer.colours[ringSlider][timeSlider][1] / 255f, skyRenderer.colours[ringSlider][timeSlider][0] / 255f];
			igColorPicker3("Colour", col);
			skyRenderer.colours[ringSlider][timeSlider] = [cast(ubyte)(col[2] * 255), cast(ubyte)(col[1] * 255), cast(ubyte)(col[0] * 255), 255];
			skyRenderer.colourMap.upload(skyRenderer.colours.ptr, TimeDivisions, Rings, Filter.linear, Filter.linear, false, true);
		}
	}
}

struct SkyComponent
{
	float horizScale;
	float vertScale;
	VirtualTime time;
}

Entity createSkyEntity(EntityManager em, Vector3f pos, float horizScale, float vertScale, VirtualTime time, bool semantic = false)
{
	Entity entity = new Entity(em);
	SkyComponent* skyComp = entity.createComponent!SkyComponent;
	skyComp.horizScale = horizScale;
	skyComp.vertScale = vertScale;
	skyComp.time = time;
	Transform* transformComp = entity.createComponent!Transform;
	transformComp.position = pos;
	transformComp.rotation = Vector3f(0f, 0f, 0f);
	transformComp.scale = Vector3f(1f, 1f, 1f);

	if(semantic)
	{
		NetworkSemantic* networkSemantic = entity.createComponent!NetworkSemantic;
		networkSemantic.syncLifetime = SyncLifetime.omnipresent;
	}

	return entity;
}