module squareone.scenes.splash;

import moxane.core;
import moxane.core.asset;
import moxane.graphics.transformation;
import moxane.graphics.texture;
import moxane.ui;
import moxane.io : Window;

import dlib.math;

final class SplashscreenScene : Scene
{
	Entity testButton;
	EntityManager em;

	this(Moxane moxane, SceneManager manager, Scene parent = null)
	{
		super(moxane, manager, parent);

		em = moxane.services.get!EntityManager;

		testButton = new Entity(em);
		em.add(testButton);
		Transform* t = testButton.createComponent!Transform;
		*t = Transform.init;
		t.position.x = 0f;
		t.position.y = 0f;
		UIPicture* p = testButton.createComponent!UIPicture;
		p.offset = Vector2i(0, 0);
		p.dimensions = moxane.services.get!Window().framebufferSize;
		p.texture = new Texture2D(AssetManager.translateToAbsoluteDir("content/backgrounds/splash.png"));
	}

	~this()
	{
		em.removeSoftAndDealloc(testButton);
	}

	override void setToCurrent(Scene overwrote)
	{
		em ~= testButton;
	}

	override void removedCurrent(Scene overwroteBy) 
	{
		em.remove(testButton);
	}

	override void onUpdate()
	{
		testButton.get!UIPicture().dimensions = moxane.services.get!Window().framebufferSize;
		mixin PropagateChildren!("onUpdate");
	}

	override void onRender()
	{
		mixin PropagateChildren!("onRender");
	}
}