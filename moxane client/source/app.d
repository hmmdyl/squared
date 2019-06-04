import std.stdio;

import moxane.core;
import moxane.graphics.renderer;
import moxane.graphics.sprite;
import moxane.io;
import moxane.ui;
import squareone.scenes.splash;

import dlib.math;

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
		sceneSystem : true
	};
	Moxane moxane = new Moxane(settings, "Square One");

	Window win = moxane.services.get!Window;
	Renderer r = moxane.services.get!Renderer;
	EntityManager entityManager = moxane.services.get!EntityManager;
	SceneManager sceneManager = moxane.services.get!SceneManager;
	moxane.services.register!SpriteRenderer(new SpriteRenderer(moxane, r));
	r.uiRenderables ~= moxane.services.get!SpriteRenderer;

	r.primaryCamera.perspective.fieldOfView = 90f;
	r.primaryCamera.perspective.near = 0.1f;
	r.primaryCamera.perspective.far = 10f;
	r.primaryCamera.isOrtho = false;
	r.primaryCamera.position = Vector3f(0f, 0f, 0f);
	r.primaryCamera.rotation = Vector3f(0f, 0f, 0f);
	r.primaryCamera.buildView;
	r.primaryCamera.buildProjection;

	win.onFramebufferResize.add((win, size) @trusted {
		r.primaryCamera.width = size.x;
		r.primaryCamera.height = size.y;
		r.primaryCamera.buildProjection;
		r.uiCamera.width = size.x;
		r.uiCamera.height = size.y;
		r.uiCamera.deduceOrtho;
		r.uiCamera.buildProjection;
		r.cameraUpdated;
	});

	entityManager.add(new UISystem(moxane, entityManager));

	sceneManager.current = new SplashscreenScene(moxane, sceneManager, null);

	moxane.run;
}
