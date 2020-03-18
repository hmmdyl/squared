module squareone.systems.inventory3;

import moxane.core;
import moxane.graphics.rendertexture;

class Inventory
{
	string name;
	string technical;

	private ubyte width, height;
	private ubyte iconWidth, iconHeight;

	bool hot;
	ubyte hotSelection;
	
	Entity[] slots;

	private RenderTexture canvas;

	void updateCanvas()
	{
		 
	}
}