module squareone.scenes.splash;

import moxane.core;

import moxane.ui.ecs;

final class SplashscreenScene : Scene
{
	Entity testButton;

	this(Moxane moxane, Scene parent = null)
	{
		super(moxane, parent);

		testButton = new Entity;
		UIButton* b = testButton.createComponent!UIButton;
		
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