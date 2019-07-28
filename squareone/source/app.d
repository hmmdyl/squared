import std.stdio;

import moxane.core;
import moxane.graphics.renderer;
import moxane.graphics.sprite;
import moxane.io;
import moxane.ui;
import squareone.scenes.dbg;
import moxane.graphics.imgui;

import dlib.math;

extern(C) export ulong NvOptimusEnablement = 0x01;

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
	moxane.services.register!SpriteRenderer(new SpriteRenderer(moxane, r));
	r.uiRenderables ~= moxane.services.get!SpriteRenderer;

	ImguiRenderer imguiRenderer = new ImguiRenderer(moxane);
	imguiRenderer.renderables ~= new RendererDebugAttachment(r);
	moxane.services.register!ImguiRenderer(imguiRenderer);
	r.uiRenderables ~= imguiRenderer;

	entityManager.add(new UISystem(moxane, entityManager));

	sceneManager.current = new DebugGameScene(moxane, sceneManager, null);

	moxane.run;
}
