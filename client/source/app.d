import std.stdio;

import squareone.common.meta;

import moxane.core;
import moxane.network;

void main()
{
	const MoxaneBootSettings boot =
	{
		logSystem : true,
		windowSystem : true,
		graphicsSystem : false,
		assetSystem : true,
		physicsSystem : false,
		networkSystem : false,
		settingsSystem : false,
		asyncSystem : true,
		entitySystem : false,
		sceneSystem : true,
		inputSystem : true,
	};
	auto moxane = new Moxane(boot, currentVersionStr);

	SceneManager scenes = moxane.services.get!SceneManager;
	scenes.current = new DebugServer(moxane, scenes);

	moxane.run;
}

final class DebugServer : Scene
{
	Client network;

	this(Moxane moxane, SceneManager manager, Scene parent = null)
	in { assert(moxane !is null); assert(manager !is null); assert(parent is null); }
	do {
		super(moxane, manager, parent);

		network = new Client("127.0.0.1", 9956, "dyl");
	}

	override void setToCurrent(Scene overwrote) {
	}

	override void removedCurrent(Scene overwroteBy) {
	}

	override void onUpdate() @trusted {
		network.update;
	}

	override void onRender() {
	}
}
