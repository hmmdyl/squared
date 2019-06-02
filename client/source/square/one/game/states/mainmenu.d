module square.one.game.states.mainmenu;

import square.one.engine;

import square.one.graphics.ui.button;
import square.one.game.states.debuggame;

import moxana.graphics.distribute;
import moxana.graphics.rendercontext;
import moxana.state;
import moxana.io.kbm;
import moxana.graphics.view;
import moxana.graphics.rh;

	
import std.container.array;
import std.range;

import dlib.math;

class MainMenuOption {
	string name;
	void delegate(MainMenuOption) onClick;
	
	private ColourButton button;
	
	this(string name, void delegate(MainMenuOption) onClick) {
		this.name = name;
		this.onClick = onClick;
		this.button = new ColourButton();
		this.button.text = name;
	}
}

static class MainMenuResources {
	private static Array!MainMenuOption options;
	
	static void add(MainMenuOption mmo, size_t index = -1) {
		if(index == -1)
			options.insert(mmo);
		else {
			if(index >= options.length)
				options.insert(mmo);
			else 
				options.insertAfter(take(options[], index), mmo);
		}
	}
}

final class MainMenu : IState {
	RenderContext rc;
	Distributor rd;

	MainMenuRenderer renderer;

	void open() {
		rc = engine.renderContext;

		renderer = new MainMenuRenderer;

		MainMenuResources.add(new MainMenuOption("Play [debug]", &runGame));
		MainMenuResources.add(new MainMenuOption("Exit", &crash));

		rc.uiRenderables.insert(renderer);
	}

	void runGame(MainMenuOption mmo) {
		engine.stateManager.push(new DebugGameState);
	}

	void crash(MainMenuOption mmo) {
		engine.shouldRun = false;
	}
	
	void close() {
		rc.uiRenderables.remove(renderer);
		destroy(rd);
	}
	
	void shadow(IState state) {
		rc.uiRenderables.remove(renderer);
	}
	
	void reveal() {
		rc.uiRenderables.insert(renderer);
	}

	void update(double previousFrameTime) {
		foreach(MainMenuOption option; MainMenuResources.options) {
			if(option.button.previous == ButtonState.click && option.button.current == ButtonState.hover) {
				if(option.onClick !is null) option.onClick(option);
			}
			
			option.button.update(cast(Vector2f)engine.window.cursorPos, engine.window.isMouseButtonDown(MouseButton.left));
		}
	}

	@property bool updateInBackground() { return false; }
}

class MainMenuRenderer : IRenderHandler {
	void shadowDepthMapPass(RenderContext rc, ref LocalRenderContext lrc) {}
	void renderPhysical(RenderContext rc, ref LocalRenderContext lrc) {}
	void renderPostPhysical(RenderContext rc, ref LocalRenderContext lrc) {}

	void ui(RenderContext rc) {
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
		
		foreach(MainMenuOption option; MainMenuResources.options) {
			option.button.position = Vector2f(startX, penY);
			option.button.size = Vector2f(width, height);
			option.button.font = engine.roboto16;
			option.button.textPos = Vector2f(fontStartX, fontPenY);
			option.button.text = option.name;
			
			option.button.inactiveColour = rgbaToVec(30, 30, 30, 128);
			option.button.hoverColour = rgbaToVec(128, 128, 128, 255);
			option.button.clickColour = rgbaToVec(25.5, 153, 255, 255);
			option.button.textColour = rgbaToVec(255, 255, 255, 255).xyz;
			
			option.button.render();
			
			penY += skip;
			fontPenY += skip;
		}
	}
}