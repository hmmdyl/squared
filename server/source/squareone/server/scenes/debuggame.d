module squareone.server.scenes.debuggame;

import moxane.core;
import moxane.network;

final class DebugServer : Scene
{
	ServiceRegistry services;

	Server network;

	this(Moxane moxane, SceneManager manager, Scene parent = null)
		in { assert(moxane !is null); assert(manager !is null); assert(parent is null); }
	do {
		super(moxane, manager, parent);

		network = new Server(["NA"], 9956);
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
