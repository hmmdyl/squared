module square.one.game.states.pause;

/*import moxana.graphics.rendercontext;
import moxana.graphics.rh;
import moxana.io.kbm;

import square.one.graphics.ui.button;

import square.one.engine;

import gfm.math;

// TODO: make look nice and modular.

class PauseSubState {
	private enum ButtonSlot {
		onResume = 0,
		onSaveAndExit = 1,
	}

	private static immutable string[] buttonTexts = [
		"Resume",
		"Save and exit"
	];

	void delegate() onResume;
	void delegate() onSaveAndExit;

	private ColourButton[] buttons;

	SquareOneEngine engine;
	RenderContext rc;

	this(void delegate() onResume, void delegate() onSaveAndExit, RenderContext rc = null) {
		this.onResume = onResume;
		this.onSaveAndExit = onSaveAndExit;
		this.rc = rc is null ? Engine.instance.renderContext : rc;

		buttons = [
			new ColourButton,
			new ColourButton
		];
	}

	void update() {
		foreach(int i, ColourButton button; buttons) {
			if(button.previous == ButtonState.click && button.current == ButtonState.hover) {
				if(i == 0) {
					if(onResume !is null)
						onResume();
				}
				if(i == 1) {
					if(onSaveAndExit !is null)
						onSaveAndExit();
				}
			}
			
			button.update(cast(vec2f)engine.window.cursorPos, engine.window.isMouseButtonDown(MouseButton.left));
		}
	}

	void render() {

	}
}

class PauseSubStateRenderer : IRenderHandler {
	PauseSubState pause;

	this(PauseSubState pause) { this.pause = pause; }

	void render(RenderContext rc) {
		enum float guiScale = 1.0f;

		float startX = rc.window.framebufferSize.x * 0.05f;
		float startY = rc.window.framebufferSize.y * 0.2f;
		float width = 400 * guiScale;
		float height = 30 * guiScale;
		float skip = height + (15 * guiScale);
		float penY = startY;
		
		float fontStartX = startX + (width * 0.05f);
		float fontStartY = startY + (8 * guiScale);
		float fontPenY = fontStartY;
		
		import moxana.graphics.rgbconv;
		
		foreach(int i, ColourButton button; pause.buttons) {
			button.position = vec2f(startX, penY);
			button.size = vec2f(width, height);
			button.font = pause.engine.roboto16;
			button.textPos = vec2f(fontStartX, fontPenY);
			button.text = PauseSubState.buttonTexts[i];
			
			button.inactiveColour = rgbaToVec(30, 30, 30, 128);
			button.hoverColour = rgbaToVec(128, 128, 128, 255);
			button.clickColour = rgbaToVec(25.5, 153, 255, 255);
			button.textColour = rgbaToVec(255, 255, 255, 255).xyz;
			
			button.render();
			
			penY += skip;
			fontPenY += skip;
		}
	}
}*/