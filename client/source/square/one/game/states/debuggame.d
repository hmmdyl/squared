module square.one.game.states.debuggame;

import moxana.state;
import moxana.graphics.view;
import moxana.graphics.distribute;
import moxana.graphics.light;
import moxana.io.kbm;

import square.one.engine;
import square.one.game.states.pause;

import square.one.graphics.ui.picture;
import square.one.graphics.camera;
import square.one.misc.sky;

import square.one.terrain.basic.manager;
import square.one.terrain.resources;

import derelict.opengl3.gl3;
import gfm.math;

import square.one.ingametime.ingametime;

import std.datetime.stopwatch;
import core.stdc.stdio;
import core.memory;
import resusage.memory;

import square.one.voxelcon.block.processor;
import std.string;
import moxana.graphics.rh;

class DebugGameState : IState {
	RenderDistributor distributor;
	RenderContext rc;
	//PauseSubState pause;

	Camera camera;

	Resources resources;
	BasicTerrainManager tm;
	BasicTerrainRenderer tr;

	IngameTime gameTime;
	StopWatch time;

	Sky sky;

	private BlockProcessor bp;

	PointLight pl;

	DebugStatsRenderer dsr;
	Crosshair crosshair;

	this() {
		rc = engine.renderContext;

		//pause = new PauseSubState(&onResume, &onSaveAndExit);

		View view = new View;
		engine.renderContext.view = view;
		view.position = vec3f(0f, 4f, 0f);
		camera = new Camera(view);

		sky = new Sky(view);
		sky.playerPosition = view.position;
		rc.directionalLights.insert(sky.sunLight);
		rc.postPhysicalRenderables.insert(sky);

		resources = new Resources;

		{
			import square.one.voxelcon.block.materials;
			import square.one.voxelcon.block.meshes;
			import square.one.voxelcon.block.textures;

			IBlockVoxelTexture[] bvts = new IBlockVoxelTexture[](2);
			bvts[0] = new DirtTexture;
			bvts[1] = new GrassTexture;
			bp = new BlockProcessor(bvts);
			resources.add(bp);
			resources.add(new Invisible);
			resources.add(new Cube);
			resources.add(new Slope);
			resources.add(new Tetrahedron);
			resources.add(new AntiTetrahedron);
			resources.add(new HorizontalSlope);
			resources.add(new Air);
			resources.add(new Dirt);
			resources.add(new Grass);
		}

		BasicTmSettings tms = BasicTmSettings.createDefault(resources, null, null, null);
		tm = new BasicTerrainManager(tms);
		tr = new BasicTerrainRenderer(tm);

		rc.physicalRenderables.insert(tr);

		//distributor = new RenderDistributor;
		//distributor.rc = rc;

		{
			pl = new PointLight;
			pl.ambientIntensity = 0f;
			pl.diffuseIntensity = 10f;
			pl.position = vec3f(0f, 4f, 0);
			pl.colour = vec3f(0.1f, 0.5f, 1f);
			pl.constAtt = 0.5f;
			pl.linAtt = 0.95f;
			pl.expAtt = 0.3f;
			//rc.pointLightWithShadow.insert(pl);
			rc.pointLights.insert(pl);
		}

		gameTime = IngameTime(8, 0);
		time = StopWatch(AutoStart.yes);

		sysMemInfo = systemMemInfo;
		procMemInfo = processMemInfo;

		//et = new EditTool;

		dsr = new DebugStatsRenderer;
		dsr.s = this;

		crosshair = new Crosshair;

		import core.memory;
		GC.collect;

		sky.update(IngameTime(8, 0));
	}

	void open() {
		rc.uiRenderables.insert(dsr);
		rc.uiRenderables.insert(crosshair);
		rc.window.hideCursor = true;
	}

	void close() {
		rc.uiRenderables.remove(dsr);
		rc.uiRenderables.remove(crosshair);
		rc.window.hideCursor = false;
	}

	void shadow(IState state) {
		rc.uiRenderables.remove(dsr);
		rc.uiRenderables.remove(crosshair);
		rc.window.hideCursor = false;
	}

	void reveal() {
		rc.uiRenderables.insert(dsr);
		rc.uiRenderables.insert(crosshair);
		rc.window.hideCursor = true;
	}

	private double prevX = 0.0, prevY = 0.0;
	private float leftOverTime = 0f;
	private enum float irlSecindsToGameSeconds = 1f / 60f;

	SystemMemInfo sysMemInfo;
	ProcessMemInfo procMemInfo;

	//EditTool et;
	bool prevBreakDown, prevPlaceDown;

	vec3l de;

	void update(double previousFrameTime) {
		import derelict.glfw3.glfw3;

		if(engine.window.isFocused) {
			double nx, ny;
			vec2d n = engine.window.cursorPos;
			nx = n.x;
			ny = n.y;
			
			double cx = nx - prevX;
			double cy = ny - prevY;

			vec2d winSize = vec2d(engine.window.size);
			winSize.x /= 2;
			winSize.y /= 2;

			engine.window.cursorPos = winSize;
			prevX = engine.window.cursorPos.x;
			prevY = engine.window.cursorPos.y;
			
			vec3f r; //vec3f(cast(float)cy * 0.75f, cast(float)cx * 0.75f, 0);
			r.x = cast(float)cy * cast(float)previousFrameTime * 100;
			r.y = cast(float)cx * cast(float)previousFrameTime * 100;
			r.z = 0;
			
			camera.rotate(r);

			vec3f a = vec3f(0f, 0f, 0f);

			if(engine.window.isKeyDown(GLFW_KEY_W)) 
				a.z += 10f;
			if(engine.window.isKeyDown(GLFW_KEY_S))
				a.z -= 10f;
			if(engine.window.isKeyDown(GLFW_KEY_A))
				a.x -= 10f;
			if(engine.window.isKeyDown(GLFW_KEY_D))
				a.x += 10f;
			if(engine.window.isKeyDown(GLFW_KEY_Q))
				a.y -= 10f;
			if(engine.window.isKeyDown(GLFW_KEY_E))
				a.y += 10f;

			//a *= 5f;

			camera.moveOnAxes(a * cast(float)previousFrameTime);
		}

		//pl.position = camera.view.position;
		
		import derelict.glfw3.glfw3;
		import derelict.opengl3.gl3;

		/*float t = time.peek().total!"nsecs"() / 1_000_000_000f;
		import std.stdio;
		writeln(t);
		int hour = cast(int)t;
		int minute = cast(int)((t - hour) * 60);

		gameTime.hour = hour;
		gameTime.minute = minute;
		if(time.peek().total!"seconds"() >= 24)
			time.reset();*/

		/*if(time.peek().total!"msecs" >= 16) {
			gameTime.incSecond;
			time.reset();
			import std.stdio;
			writeln("Hours: ", gameTime.hour, ", minutes: ", gameTime.minute, ", second: ", gameTime.second, ", coord: ", gameTime.timeToSun);
		}*/

		float n = leftOverTime + cast(float)previousFrameTime;
		float ts = n / irlSecindsToGameSeconds;
		int ti = cast(int)ts;

		if(ti > 0) {
			foreach(tic; 0 .. ti)
				gameTime.incSecond;
			n -= (ti * irlSecindsToGameSeconds);
			leftOverTime = n;
		}
		else {
			leftOverTime = n;
		}

		//import std.stdio;
		//writeln("Hours: ", gameTime.hour, ", minutes: ", gameTime.minute, ", second: ", gameTime.second, ", coord: ", gameTime.timeToSun);

		sky.update(gameTime);
		sky.playerPosition = camera.view.position;

		if(engine.window.isKeyDown(GLFW_KEY_X))
			rc.polygonMode = GL_LINE;
		else rc.polygonMode = GL_FILL;
		
		camera.view.generateMatrix();

		//atmosphere.sunDir = gameTime.timeToSun;

		bool shouldBreak = engine.window.isMouseButtonDown(MouseButton.right) && !prevBreakDown;
		bool shouldPlace = engine.window.isMouseButtonDown(MouseButton.left) && !prevPlaceDown;
		//vec3l de;
		vec3f df;
		vec3i face;
		
		//et.update(camera.view.position, camera.view.rotation, terrainManager, shouldBreak, shouldPlace, de, df, face);
		
		prevBreakDown = engine.window.isMouseButtonDown(MouseButton.right);
		prevPlaceDown = engine.window.isMouseButtonDown(MouseButton.left);


		tm.cameraPosition = camera.view.position;
		tm.update;

		procMemInfo.update;
		sysMemInfo.update;
	}

	private void onResume() {

	}

	private void onSaveAndExit() {

	}

	@property bool updateInBackground() { return true; }
}

class DebugStatsRenderer : IRenderHandler {
	DebugGameState s;

	void shadowDepthMapPass(RenderContext rc, ref LocalRenderContext lrc) {}
	void renderPhysical(RenderContext rc, ref LocalRenderContext lrc) {}
	void renderPostPhysical(RenderContext rc, ref LocalRenderContext lrc) {}

	private char[2048] diagbuff;

	void ui(RenderContext rc) {
		int l = sprintf(diagbuff.ptr, 
			"Camera position: %0.2f, %0.2f, %0.2f
Camera rotation: %0.2f, %0.2f, %0.2f

Delta (pf): %f (s)
Delta (pf): %0.2f (ms)

Time: %s

[GC]
Used: %0.2f (MB)
Free: %0.2f (MB)

[RES]
Used: %0.2f (MB)
Virt: %0.2f (MB)
Free: %0.2f (MB)

[Block]
Lowest: %0.2f (ms)
Highest: %0.2f (ms)
Av. (r): %0.2f (ms)
T. busy: %i

[NG]
Lowest: %0.2f (ms)
Highest: %0.2f (ms)
Av. (r): %0.2f (ms)
T. busy: %i

[BTM]
Added: %i
Hibernated: %i
Rendered: %i",
			s.camera.view.position.x, s.camera.view.position.y, s.camera.view.position.z,
			s.camera.view.rotation.x, s.camera.view.rotation.y, s.camera.view.rotation.z,
			engine.previousDeltaTime, engine.previousDeltaTime * 1000,
			toStringz(s.gameTime.toString),
			GC.stats.usedSize / 1_048_576f, GC.stats.freeSize / 1_048_576f,
			s.procMemInfo.usedRAM / 1_048_576f, s.procMemInfo.usedVirtMem / 1_048_576f, s.sysMemInfo.freeRAM / 1_048_576f,
			s.bp.lowestMeshTime, s.bp.highestMeshTime, s.bp.averageMeshTime, s.bp.numMeshThreadsBusy,
			s.tm.noiseGeneratorManager.lowestTime, s.tm.noiseGeneratorManager.highestTime, s.tm.noiseGeneratorManager.averageTime,
			s.tm.noiseGeneratorManager.numBusy,
			s.tm.chunksAdded, s.tm.chunksHibernated, s.tr.renderedInFrame);
		
		engine.renderContext.textRenderer.render(engine.roboto16, cast(immutable)diagbuff, l, vec2f(-1f, 0.95f), vec3f(1f, 0.5f, 0f));
	}
}

final class Crosshair : IRenderHandler {
	private Picture picture;

	this() {
		import std.path;
		import std.file;

		picture = new Picture();
		picture.setPicture(buildPath(getcwd(), "assets/textures/crosshair_4.png"), GL_NEAREST, GL_NEAREST);
	}

	void shadowDepthMapPass(RenderContext rc, ref LocalRenderContext lrc) {}
	void renderPhysical(RenderContext rc, ref LocalRenderContext lrc) {}
	void renderPostPhysical(RenderContext rc, ref LocalRenderContext lrc) {}

	void ui(RenderContext rc) {
		vec2i windowSize = rc.window.size;
		windowSize /= 2;
		vec2i crossHairStart = vec2i(windowSize.x - 16, windowSize.y - 16);

		picture.position = cast(vec2f)crossHairStart;
		picture.size = vec2f(33f, 33f);
		engine.pictureRenderer.render(picture);
	}
}