module square.one.terrain.terraindesc;

import moxana.hierarchy.world;

class TerrainWorldDescriptor : IWorldDescriptor {
	@property string technicalName() { return TerrainWorldDescriptor.stringof; }

	World world;

	//private TerrainManager terrainManager;

	this(World world) {
		this.world = world;
	}

	void update(double dt) {

	}
}