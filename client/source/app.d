import std.stdio;

import squareone.client.scenes.game;
import squareone.common.meta;

import moxane.core;
import moxane.network;

extern(C) export ulong NvOptimusEnablement = 0x01;

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
		entitySystem : true,
		sceneSystem : true,
		inputSystem : true,
	};
	auto moxane = new Moxane(boot, currentVersionStr);

	SceneManager scenes = moxane.services.get!SceneManager;
	scenes.current = new Game(moxane, scenes);

	moxane.run;
}