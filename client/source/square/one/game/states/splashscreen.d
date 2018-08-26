module square.one.game.states.splashscreen;

import square.one.engine;
import square.one.game.states.mainmenu;
import square.one.graphics.ui.picture;

import moxana.state;
import moxana.graphics.rendercontext;
import moxana.graphics.distribute;
import moxana.graphics.rh;
import moxana.utils.loadable;

import gfm.math;

import std.datetime.stopwatch;

final class Splashscreen : IState {
	SplashscreenRenderer renderer;

	void open() {
		sw.start;

		renderer = new SplashscreenRenderer;

		engine.renderContext.uiRenderables.insert(renderer);
	}
	
	void close() {
		engine.renderContext.uiRenderables.remove(renderer);
	}
	
	void shadow(IState state) {
		engine.renderContext.uiRenderables.remove(renderer);
	}

	void reveal() {
		engine.renderContext.uiRenderables.insert(renderer);
	}
	
	StopWatch sw;
	
	void update(double previousFrameTime) {
		// TODO: init system for plugins and non-crucial services here.

		//if(engine.loadables.length > 0) {
		//	ILoadable loadable = engine.loadables.front;
		//	loadable.load;
	//		engine.loadables.remove(loadable);
		//}

		if(sw.peek().total!"msecs"() > 250/* && engine.loadables.length == 0*/) {
			StateManager man = engine.stateManager;
			man.pop;
			man.push(new MainMenu);
		}
	}
	
	@property bool updateInBackground() { return false; }
}

final class SplashscreenRenderer : IRenderHandler {
	private Picture splash;
	
	this() {
		import std.path;
		import std.file;
		
		splash = new Picture();
		splash.setPicture(buildPath(getcwd(), "assets/textures/gloriousSplashscreen.png"));
	}
	
	~this() {
		destroy(splash);
	}

	void shadowDepthMapPass(RenderContext rc, ref LocalRenderContext lrc) {}
	void renderPhysical(RenderContext rc, ref LocalRenderContext lrc) {}
	void renderPostPhysical(RenderContext rc, ref LocalRenderContext lrc) {}
	
	void ui(RenderContext rc) {
		splash.position = vec2i(0, 0);
		splash.size = cast(vec2f)rc.window.size;
		engine.pictureRenderer.render(splash);
	}
}