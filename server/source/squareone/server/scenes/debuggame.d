module squareone.server.scenes.debuggame;

import moxane.core;
import moxane.network;
import moxane.io;

import squareone.common.terrain.basic.packets;
import squareone.common.voxel;

final class DebugServer : Scene
{
	ServiceRegistry services;

	Server network;

	this(Moxane moxane, SceneManager manager, Scene parent = null)
		in { assert(moxane !is null); assert(manager !is null); assert(parent is null); }
	do {
		super(moxane, manager, parent);

		import std.stdio;
		writeln(GetPackets!(squareone.common.terrain.basic.packets));
		network = new Server(GetPackets!(squareone.common.terrain.basic.packets), 9956);
	}

	override void setToCurrent(Scene overwrote) {
	}

	override void removedCurrent(Scene overwroteBy) {
	}

	override void onUpdate() @trusted {

		if(moxane.services.get!Window().isKeyDown(Keys.a))
		{
			foreach(x; -4 .. 4)
			{
				foreach(y; -4 .. 4)
				{
					foreach(z; -4 .. 4)
					{
						VoxelUpdate u;
						u.updated = Voxel(2, 1, 0, 0);
						u.x = x;
						u.y = y;
						u.z = z;
						network.broadcast("VoxelUpdate", u);
					}
				}
			}
		}

		network.update;
	}

	override void onRender() {
	}
}
