module square.one.engine;

import moxana.engine;
import moxana.graphics.rendercontext;
import moxana.graphics.distribute;
import moxana.graphics.text;
import moxana.io.kbm;

import square.one.io.keybinds;
import square.one.settings;
import square.one.game.states.splashscreen;

import square.one.graphics.ui.picture;

import std.file : getcwd;
import std.path : buildPath;
import std.conv : to;

private __gshared SquareOneEngine sqEngine_;
@property SquareOneEngine engine() { return sqEngine_; }

final class SquareOneEngine : Engine {
	immutable string settingsFile;

	private Settings settings_;
	private KeyBinds ioBindings_;

	Font roboto16;

	int fullscreenToggleKey = -1;

	private PictureRenderer pictureRenderer_;

	this() {
		super("Square One");

		sqEngine_ = this;

		settingsFile = buildPath(getcwd, "settings.json");
	}

	void execute() {
		settings_ = new Settings;
		settings_.importJson(settingsFile);

		int w = to!int(settings_.getOrAdd("squareone.engine.windowWidthFullscreen", "0"));
		int h = to!int(settings_.getOrAdd("squareone.engine.windowHeightFullscreen", "0"));
		bool f = to!bool(settings_.getOrAdd("squareone.engine.fullscreen", "false"));

		initEngineResources(1280, 720);
		if(f)
			window.fullscreen(true, w, h);

		ioBindings_ = new KeyBinds(window, settings_);
		ioBindings_.getBindings();
		
		fullscreenToggleKey = ioBindings_.getOrAdd("squareone.engine.toggleFullscreenKey", cast(int)Keys.f1);
		ioBindings_.exportToSettings();
		ioBindings_.connect("squareone.engine.toggleFullscreenKey", &toggleFullscreen);
		
		settings_.exportJson(settingsFile);

		roboto16 = renderContext.textRenderer.loadFont(buildPath(getcwd(), "assets/fonts/roboto.ttf"), 16);

		stateManager.push(new Splashscreen);

		run;
	}

	override void onLoad() {}
	override void onUnload() {}

	private void toggleFullscreen(ButtonAction a) {
		if(a == ButtonAction.release) {
			if(window.isFullscreen) {
				window.fullscreen(false);
			}
			else window.fullscreen(true, to!int(settings.get("squareone.engine.windowWidthFullscreen")), to!int(settings.get("squareone.engine.windowHeightFullscreen")));
		}
	}

	override protected RenderContext createRenderContext() { return new RenderContext(window, true); }
	override protected RenderDistributor createRenderDistributor() { return new RenderDistributor(); }

	@property Settings settings() { return settings_; }
	@property KeyBinds ioBindings() { return ioBindings_; }
	@property PictureRenderer pictureRenderer() { if(pictureRenderer_ is null) pictureRenderer_ = new PictureRenderer; return pictureRenderer_; }
}

/*import square.one.data;

import moxana.graphics.rendercontext;
import moxana.graphics.text;

import moxana.io.window;
import moxana.io.kbm;

import moxana.state;

import moxana.utils.loadable;

import square.one.io.keybinds;
import square.one.settings;

import square.one.game.states.splashscreen;

import std.datetime.stopwatch;
import std.file : getcwd;
import std.path : buildPath;
import std.conv : to;

import containers.unrolledlist;

class Engine {
	static __gshared Engine instance;

	Window window;

	RenderContext renderContext;
	Font roboto16;

	Settings settings;
	KeyBinds ioBindings;

	StateManager stateManager;

	immutable string settingsFile;

	UnrolledList!ILoadable loadables;

	bool shouldExit = false;

	int fullscreenToggleKey = -1;

	this() {
		if(instance !is null) throw new Error("Only one " ~ Engine.stringof ~ " may exist.");
		instance = this;

		window = new Window(1920, 1080, gameName ~ " " ~ gameVersion);

		settingsFile = buildPath(getcwd, "settings.json");
		settings = new Settings;
		settings.importJson(settingsFile);

		{
			int w = to!int(settings.getOrAdd("squareone.engine.windowWidthFullscreen", "0"));
			int h = to!int(settings.getOrAdd("squareone.engine.windowHeightFullscreen", "0"));
			bool f = to!bool(settings.getOrAdd("squareone.engine.fullscreen", "false"));

			if(f)
				window.fullscreen(true, w, h);
		}

		ioBindings = new KeyBinds(window, settings);
		ioBindings.getBindings();

		fullscreenToggleKey = ioBindings.getOrAdd("squareone.engine.toggleFullscreenKey", cast(int)Keys.f1);
		ioBindings.exportToSettings();
		ioBindings.connect("squareone.engine.toggleFullscreenKey", &toggleFullscreen);

		settings.exportJson(settingsFile);

		renderContext = new RenderContext(window);
		//renderContext.load;
		loadables.insert(renderContext);

		EngineLoader el = new EngineLoader;
		loadables.insert(el);

		stateManager = new StateManager();
		stateManager.push(new Splashscreen);
	}

	private void toggleFullscreen(ButtonAction a) {
		if(a == ButtonAction.release) {
			if(window.isFullscreen) {
				window.fullscreen(false);
			}
			else window.fullscreen(true, to!int(settings.get("squareone.engine.windowWidthFullscreen")), to!int(settings.get("squareone.engine.windowHeightFullscreen")));
		}
	}

	private StopWatch deltaSw;
	private double previousDT_;
	@property double previousDeltaTime() { return previousDT_; }

	private uint frameCount = 0;
	private StopWatch oneSecondSw;

	void run() {
		oneSecondSw.start;

		while(!shouldExit) {
			deltaSw.stop;
			previousDT_ = deltaSw.peek().total!"nsecs"() / 1_000_000_000f;
			previousDT_ = previousDT_ == double.nan ? 0.0 : previousDT_;

			if(oneSecondSw.peek().total!"msecs" >= 1000) {
				oneSecondSw.reset();
				import std.stdio;
				writeln("FPS: ", frameCount, " | Av. delta: ", 1.0 / frameCount, "ms");
				frameCount = 0;
			}

			deltaSw.reset;
			deltaSw.start;

			frameCount++;

			window.pollEvents;

			shouldExit |= window.shouldClose;

			stateManager.update(previousDT_);
			stateManager.render();

			window.swapBuffers();
		}
	}
}

class EngineLoader : ILoadable {
	void load() {
		Engine.instance.roboto16 = Engine.instance.renderContext.textRenderer.loadFont(buildPath(getcwd(), "assets/fonts/roboto.ttf"), 16);
	}
}*/