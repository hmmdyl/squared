import std.stdio;

import moxane.core;
import moxane.graphics.renderer;
import moxane.graphics.sprite2;
import moxane.graphics.standard;
import moxane.graphics.ecs;
import moxane.io;
import moxane.ui;
import squareone.scenes.dbg;
import moxane.graphics.imgui;

import squareone.util.spec;
import squareone.scenes.redo;

import core.cpuid;
import std.conv : to;

import dlib.math;

extern(C) export ulong NvOptimusEnablement = 0x01;

void main()
{
	const MoxaneBootSettings settings = 
	{
		logSystem : true,
		windowSystem : true,
		graphicsSystem : false,
		assetSystem : true,
		physicsSystem : false,
		networkSystem : false,
		settingsSystem : false,
		asyncSystem : true,
		entitySystem : true,
		sceneSystem : true,
		inputSystem : true,
	};
	auto moxane = new Moxane(settings, "Square One v" 
							 ~ to!string(gameVersion[0]) ~ "."
							 ~ to!string(gameVersion[1]) ~ "."
							 ~ to!string(gameVersion[2]));

	debug 
	{
		Log log = moxane.services.get!Log;
		log.write(Log.Severity.debug_, "Vendor: " ~ vendor);
		log.write(Log.Severity.debug_, "Processor: " ~ processor);
		log.write(Log.Severity.debug_, "Hyperthreading: " ~ to!string(hyperThreading));
		log.write(Log.Severity.debug_, "Threads/CPU: " ~ to!string(threadsPerCPU));
		log.write(Log.Severity.debug_, "Cores/CPU: " ~ to!string(coresPerCPU));
	}

	SceneManager scenes = moxane.services.get!SceneManager;
	scenes.current = new RedoScene(moxane, scenes);

	moxane.run;
}

version(OLD):
void main()
{
	const MoxaneBootSettings settings = 
	{
		logSystem : true,
		windowSystem : true,
		graphicsSystem : true,
		assetSystem : true,
		physicsSystem : false,
		networkSystem : false,
		settingsSystem : false,
		asyncSystem : true,
		entitySystem : true,
		sceneSystem : true,
		inputSystem : true,
	};
	Moxane moxane = new Moxane(settings, "Square One");

	Window win = moxane.services.get!Window;
	Renderer r = moxane.services.get!Renderer;
	EntityManager entityManager = moxane.services.get!EntityManager;
	SceneManager sceneManager = moxane.services.get!SceneManager;
	moxane.services.register!Sprites(new Sprites(moxane, r));
	r.uiRenderables ~= moxane.services.get!Sprites;

	ImguiRenderer imguiRenderer = new ImguiRenderer(moxane);
	imguiRenderer.renderables ~= new RendererDebugAttachment(r);
	moxane.services.register!ImguiRenderer(imguiRenderer);
	r.uiRenderables ~= imguiRenderer;

	entityManager.add(new UISystem(moxane, entityManager));

	StandardRenderer sr = new StandardRenderer(moxane);
	moxane.services.register!StandardRenderer(sr);
	r.addSceneRenderable(sr);
	auto ers = new EntityRenderSystem(moxane);
	moxane.services.register!EntityRenderSystem(ers);

	sceneManager.current = new DebugGameScene(moxane, sceneManager, null);

	Log log = moxane.services.get!Log;
	log.write(Log.Severity.debug_, "Vendor: " ~ vendor);
	log.write(Log.Severity.debug_, "Processor: " ~ processor);
	log.write(Log.Severity.debug_, "Hyperthreading: " ~ to!string(hyperThreading));
	log.write(Log.Severity.debug_, "Threads/CPU: " ~ to!string(threadsPerCPU));
	log.write(Log.Severity.debug_, "Cores/CPU: " ~ to!string(coresPerCPU));

	moxane.run;
}
