module squareone.scenes.splash;

import moxane.core;
import moxane.graphics.transformation;
import moxane.ui;

import dlib.math;

final class SplashscreenScene : Scene
{
	Entity testButton;

	this(Moxane moxane, Scene parent = null)
	{
		super(moxane, parent);

		testButton = new Entity;
		moxane.services.get!EntityManager().add(testButton);
		Transform* t = testButton.createComponent!Transform;
		*t = Transform.init;
		t.position.x = 20f;
		t.position.y = 20f;
		UIButton* b = testButton.createComponent!UIButton;
		b.offset = Vector2i(0, 0);
		b.dimensions = Vector2i(100, 20);
		b.inactiveColour = Vector4f(1f, 0.5f, 0.1f, 1f);
		b.hoverColour = Vector4f(0f, 1f, 0.1f, 1f);
		b.clickColour = Vector4f(0f, 0f, 1f, 1f);
	}

	override void setToCurrent(Scene overwrote)
	{

	}

	override void removedCurrent(Scene overwroteBy) 
	{
		
	}

	override void onUpdate()
	{
		mixin PropagateChildren!("onUpdate");
	}

	override void onRender()
	{
		mixin PropagateChildren!("onRender");
	}
}