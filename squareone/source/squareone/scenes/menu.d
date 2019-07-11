module squareone.scenes.menu;

import moxane.core;
import moxane.graphics.renderer;
import moxane.graphics.texture;
import moxane.graphics.sprite;
import moxane.ui;
import moxane.io;

import dlib.math.vector : Vector2i;

final class MainMenu : Scene
{
	Texture2D backgroundTexture;

	private Entity background;
	private Entity title;
	private Entity singlePlayer;
	private Entity multiPlayer;
	private Entity options;
	private Entity exit;

	override void onUpdate()
	{
		mixin PropagateChildren!("onUpdate");
	}

	private void 
}