import std.stdio;

import squareone.server.scenes.debuggame;
import squareone.common.meta;

import moxane.core;

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
