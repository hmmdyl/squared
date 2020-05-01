module squareone.client.systems.sky;

import squareone.client.systems.time;
import moxane.core;
import moxane.graphics.redo;
import moxane.graphics.assimp;
import moxane.graphics.imgui;
import moxane.network.semantic;

import std.algorithm.searching : canFind;
import derelict.opengl3.gl3;
import containers.unrolledlist;
import dlib.math.vector;
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

alias SkyRenderer7R24D = SkyRenderer!(11, 24);

class SkyObjects
{
	private Texture2D sun, moon;

	private GLuint vao, vb, tb;
	private enum vertexCount = 6;

	private Effect effect;

	this(Moxane moxane, Texture2D sun, Texture2D moon)
	in(moxane !is null) in(sun !is null) in(moon !is null)
	{
		this.sun = sun;
		this.moon = moon;

		Log log = moxane.services.get!Log;
		Shader vs = new Shader, fs = new Shader;
		vs.compile(readText(AssetManager.translateToAbsoluteDir("content/shaders/skyObject.vs.glsl")), 
				   GL_VERTEX_SHADER, log);
		fs.compile(readText(AssetManager.translateToAbsoluteDir("content/shaders/skyObject.fs.glsl")), 
				   GL_FRAGMENT_SHADER, log);
		effect = new Effect(moxane, SkyObjects.stringof);
		with(effect)
		{
			attachAndLink(vs, fs);
			bind;
			findUniform("MVP");
			findUniform("Model");
			findUniform("Texture");
			unbind;
		}

		glGenVertexArrays(1, &vao);
		glGenBuffers(1, &vb);
		glGenBuffers(1, &tb);

		Vector3f[] vertices = [
			Vector3f(-25, 0, -25),
			Vector3f(-25, 0, 25),
			Vector3f(25, 0, 25),

			Vector3f(25, 0, 25),
			Vector3f(25, 0, -25),
			Vector3f(-25, 0, -25),
		];
		Vector2f[] texCoords = [
			Vector2f(0, 0),
			Vector2f(0, 1),
			Vector2f(1, 1),

			Vector2f(1, 1),
			Vector2f(1, 0),
			Vector2f(0, 0)
		];

		glBindBuffer(GL_ARRAY_BUFFER, vb);
		glBufferData(GL_ARRAY_BUFFER, vertices.length * Vector3f.sizeof, vertices.ptr, GL_STATIC_DRAW);
		glBindBuffer(GL_ARRAY_BUFFER, tb);
		glBufferData(GL_ARRAY_BUFFER, texCoords.length * Vector2f.sizeof, texCoords.ptr, GL_STATIC_DRAW);
		glBindBuffer(GL_ARRAY_BUFFER, 0);
	}

	~this()
	{
		glDeleteBuffers(1, &vb);
		glDeleteBuffers(1, &tb);
		glDeleteVertexArrays(1, &vao);
	}

	private void render(Vector3f sunPos, Vector3f moonPos, Vector3f target, Pipeline pipeline, 
						ref LocalContext lc, ref PipelineStatics stats)
	{
		glBindVertexArray(vao);
		scope(exit) glBindVertexArray(0);

		glEnableVertexAttribArray(0);
		scope(exit) glDisableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		scope(exit) glDisableVertexAttribArray(1);

		pipeline.openGL.blend.push(true);
		scope(exit) pipeline.openGL.blend.pop;

		effect.bind;
		scope(exit) effect.unbind;
		glActiveTexture(GL_TEXTURE0);
		effect["Texture"].set(0);

		Vector3f dirToTarget = sunPos - target;
		dirToTarget.normalize;

		import dlib.math : degtorad;
		import std.math : abs;

		float y = -(dirToTarget.y);
		y *= 90f;
		y += 90f;
		if(dirToTarget.z > 0) y = -y;

		Matrix4f sunM = translationMatrix(sunPos) * rotationMatrix(0, degtorad(y));

		dirToTarget = moonPos - target;
		dirToTarget.normalize;
		y = -(dirToTarget.y);
		y *= 90f;
		y += 90f;
		if(dirToTarget.z > 0) y = -y;

		Matrix4f moonM = translationMatrix(moonPos) * rotationMatrix(0, degtorad(y));
		Matrix4f mvp = lc.camera.projection * lc.camera.viewMatrix * sunM;

		sun.bind;
		effect["Model"].set(&sunM);
		effect["MVP"].set(&mvp);

		glBindBuffer(GL_ARRAY_BUFFER, vb);
		glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, tb);
		glVertexAttribPointer(1, 2, GL_FLOAT, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		glDrawArrays(GL_TRIANGLES, 0, vertexCount);
		sun.unbind;

		moon.bind;
		mvp = lc.camera.projection * lc.camera.viewMatrix * moonM;
		effect["Model"].set(&moonM);
		effect["MVP"].set(&mvp);

		glDrawArrays(GL_TRIANGLES, 0, vertexCount);
		moon.unbind;

		stats.drawCalls += 2;
		stats.vertexCount += vertexCount * 2;
	}
}

class SkyRenderer(int Rings, int TimeDivisions) : IDrawable
{
	SkySystem skySystem;

	private uint vao;
	private uint vertexBO;
	private uint vertexCount;

	private Effect skyEffect;
	private Texture2D colourMap;

	SkyObjects objects;

	private ubyte[4][TimeDivisions][Rings] colours;

	this(Moxane moxane, SkySystem skySystem)
	in(moxane !is null)
	in(skySystem !is null)
	{
		this.skySystem = skySystem;

		glGenVertexArrays(1, &vao);

		Vector3f[] verts;
		loadMesh!(Vector3f, GCAllocator)(AssetManager.translateToAbsoluteDir("content/models/skySphere80.dae"), verts);
		scope(exit) GCAllocator.instance.deallocate(verts);

		vertexCount = cast(uint)verts.length;

		glGenBuffers(1, &vertexBO);
		glBindBuffer(GL_ARRAY_BUFFER, vertexBO);
		scope(exit) glBindBuffer(GL_ARRAY_BUFFER, 0);

		glBufferData(GL_ARRAY_BUFFER, verts.length * Vector3f.sizeof, verts.ptr, GL_STATIC_DRAW);

		foreach(d; 0 .. TimeDivisions)
			foreach(r; 0 .. Rings)
				colours[r][d] = [255, 255, 0, 255];

		string dir = AssetManager.translateToAbsoluteDir("skyColourMap.txt");
		import std.file;
		if(exists(dir))
		{
			Log log = moxane.services.get!Log;
			log.write(Log.Severity.info, "Loading SkyRenderer colour map...");
			scope(success) log.write(Log.Severity.info, "Loaded");
			ubyte[] bytes = cast(ubyte[])read(dir);
			//importColourMap(bytes);
		}

		colourMap = new Texture2D(colours.ptr, TimeDivisions, Rings, TextureBitDepth.eight,
								  Filter.linear, Filter.linear, false, true);

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
		skyEffect.findUniform("MaxHeight");
		skyEffect.unbind;
	}

	~this()
	{
		glDeleteVertexArrays(1, &vao);
	}

	void draw(Pipeline pipeline, ref LocalContext lc, ref PipelineStatics stats) @trusted
	{
		if(skySystem.skyBox is null) 
			return;

		synchronized(skySystem)
		{
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

			Matrix4f m = /+lc.inheritedModel *+/ transform.matrix * scaleMatrix(Vector3f(sky.horizScale, sky.vertScale, sky.horizScale));
			Matrix4f mvp = lc.camera.projection * lc.camera.viewMatrix * m;

			skyEffect["Model"].set(&m);
			skyEffect["MVP"].set(&mvp);
			skyEffect["MaxHeight"].set(sky.vertScale);

			skyEffect["Time"].set((sky.time.decimal + 0.5f) / VirtualTime.maxHour);

			glBindBuffer(GL_ARRAY_BUFFER, vertexBO);
			glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, null);
			scope(exit) glBindBuffer(GL_ARRAY_BUFFER, 0);

			glDrawArrays(GL_TRIANGLES, 0, vertexCount);

			stats.drawCalls += 1;
			stats.vertexCount += vertexCount;

			if(objects !is null)
			{
				objects.render(sunPos, moonPos, transform.position, 
							   pipeline, lc, stats);
			}
		}
	}

	@property Vector3f sunDir()
	{
		assert(skySystem !is null);
		SkyComponent* sky = skySystem.skyBox.get!SkyComponent;
		assert(sky !is null);

		import std.math : sin, cos;
		import dlib.math : degtorad;

		auto asRadian = degtorad(sky.time.decimal * (360f / 24f));
		return Vector3f(0f, -cos(asRadian), sin(asRadian));
	}

	@property Vector3f sunPos()
	{
		SkyComponent* sky = skySystem.skyBox.get!SkyComponent;
		Transform* t = skySystem.skyBox.get!Transform;
		return t.position + sunDir * Vector3f(1, sky.vertScale * 0.85, sky.horizScale * 0.85);
	}

	@property Vector3f moonPos() 
	{
		SkyComponent* sky = skySystem.skyBox.get!SkyComponent;
		Transform* t = skySystem.skyBox.get!Transform;
		return t.position - sunDir * Vector3f(1, sky.vertScale * 0.85, sky.horizScale * 0.85);
	}

	@property Vector3f fogColour()
	{
		import dlib.math.interpolation.linear : interpLinear;
		import std.math : pow;
		const SkyComponent* sky = skySystem.skyBox.get!SkyComponent;
		immutable division = sky.time.hour * (TimeDivisions / 24);
		immutable nextDivision = (division + 1) % TimeDivisions;
		immutable linPos = (sky.time.minute % (60 / (TimeDivisions / 24))) / cast(float)(60 / (TimeDivisions / 24));
		auto divisionColour = Vector3f(colours[0][division][2] / 255f, colours[0][division][1] / 255f, colours[0][division][0] / 255f);
		auto nextDivisionColour = Vector3f(colours[0][nextDivision][2] / 255f, colours[0][nextDivision][1] / 255f, colours[0][nextDivision][0] / 255f);
		Vector3f colour;
		colour.r = interpLinear(divisionColour.r, nextDivisionColour.r, linPos);
		colour.g = interpLinear(divisionColour.g, nextDivisionColour.g, linPos);
		colour.b = interpLinear(divisionColour.b, nextDivisionColour.b, linPos);
		return colour;
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

	/+static final class DebugAttachment : IImguiRenderable
	{
	SkyRenderer!(Rings, TimeDivisions) skyRenderer;
	Moxane moxane;

	this(SkyRenderer!(Rings, TimeDivisions) sky, Moxane moxane) { this.skyRenderer = sky; this.moxane = moxane; }

	private int timeSlider;
	private int ringSlider;

	private float expGradient = 1f;
	private float expN0 = 1f;

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

	if(igButton("Linear gradient"))
	{
	ubyte[4] base = skyRenderer.colours[0][timeSlider];
	ubyte[4] top = skyRenderer.colours[Rings-1][timeSlider];

	foreach(r; 1 .. Rings-1)
	{
	ubyte[4] lerpCol;
	import dlib.math.interpolation;
	lerpCol[0] = cast(ubyte)interpLinear!float(base[0], top[0], cast(float)r / Rings);
	lerpCol[1] = cast(ubyte)interpLinear!float(base[1], top[1], cast(float)r / Rings);
	lerpCol[2] = cast(ubyte)interpLinear!float(base[2], top[2], cast(float)r / Rings);
	lerpCol[3] = 255;
	skyRenderer.colours[r][timeSlider] = lerpCol;
	}
	}
	igSliderFloat("Exp base", &expGradient, 0, 10);
	igSliderFloat("Exp N0", &expN0, 0, 10);
	if(igButton("Exp gradient"))
	{
	ubyte[4] base = skyRenderer.colours[0][timeSlider];
	ubyte[4] top = skyRenderer.colours[Rings-1][timeSlider];

	foreach(r; 0 .. Rings)
	{
	ubyte[4] lerpCol;
	import dlib.math.interpolation;
	import dlib.math.utils;
	import std.math;
	float l = expN0 * exp((cast(float)r / cast(float)Rings) * -expGradient);
	l = clamp(l, 0, 1);
	foreach(c; 0 .. 3)
	lerpCol[c] = cast(ubyte)clamp(interpLinear!float(top[c], base[c], l), 0, 255);
	lerpCol[3] = 255;
	skyRenderer.colours[r][timeSlider] = lerpCol;
	}
	}

	Texture2D.ConstructionInfo ci;
	ci.bitDepth = TextureBitDepth.eight;
	ci.clamp = true;
	ci.mipMaps = false;
	ci.minification = Filter.linear;
	ci.magnification = Filter.linear;
	ci.srgb = false;
	skyRenderer.colourMap.upload(skyRenderer.colours.ptr, TimeDivisions, Rings, ci);
	}
	}+/
}

@Component
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