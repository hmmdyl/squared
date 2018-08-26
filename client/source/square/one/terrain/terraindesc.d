module square.one.terrain.terraindesc;

import moxana.hierarchy.world;

import square.one.terrain.manager;

class TerrainWorldDescriptor : IWorldDescriptor {
	@property string technicalName() { return TerrainWorldDescriptor.stringof; }

	World world;

	private TerrainManager terrainManager;

	this(World world, TerrainManagerCreateInfo info) {
		this.world = world;
	}

	void update(double dt) {

	}
}