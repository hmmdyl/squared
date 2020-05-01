module squareone.client.scenes.game;

import squareone.client.terrain.basic.engine : TerrainEngine, TerrainSettings;
import squareone.client.terrain.basic.renderer;
import squareone.common.terrain.basic.packets;
import squareone.common.voxel;
import squareone.common.content.voxel.block;
import squareone.client.content.voxel.block;

import squareone.client.systems.sky;
import squareone.client.systems.time;

import moxane.core;
import moxane.graphics.redo;
import moxane.network;

import dlib.math;

@safe:

final class Game : Scene
{
	private Pipeline pipeline;
	private Camera camera;

	private TerrainEngine terrain;
	private TerrainRenderer terrainRenderer;

	private EntityManager em;

	private Client client;

	this(Moxane moxane, SceneManager manager) @trusted
	in { assert(moxane !is null); assert(manager !is null); }
	do {
		super(moxane, manager, null);

		em = new EntityManager(moxane, this);
		moxane.services.register!EntityManager(em);

		client = new Client("127.0.0.1", 9956, "dylan");
		client.onLoginComplete.addCallback(&onLoginComplete);

		initGraphics;
		initTerrainEngine;
	}

	private void onLoginComplete(ref LoginVerificationPacket packet)
	{
		client.event("VoxelUpdate").addCallback(&onVoxelUpdate);
	}

	private void onVoxelUpdate(ref ClientIncomingPacket packet)
	{
		import cerealed;
		VoxelUpdate p = decerealize!VoxelUpdate(packet[1]);

		terrain.voxelInteraction.set(p.updated, BlockPosition(p.x, p.y, p.z));
	}

	private void initGraphics()
	{
		pipeline = new Pipeline(moxane, this);
		camera = new Camera;
		camera.perspective.fieldOfView = 75f;
		camera.perspective.near = 0.1f;
		camera.perspective.far = 600f;
		camera.width = cast(uint)pipeline.window.framebufferSize.x;
		camera.height = cast(uint)pipeline.window.framebufferSize.y;
		camera.isOrtho = false;
		camera.position = Vector3f(-2, 5f, 0);
		camera.rotation = Vector3f(90, 90, 0);
		camera.buildProjection;
		camera.buildView;
		pipeline.fog.colour = Vector3f(1, 0, 0);
	}

	private void initTerrainEngine() @trusted
	{
		VoxelRegistry registry = new VoxelRegistry();
		registry.add(new Invisible);
		registry.add(new Air);

		IBlockVoxelTexture[] bvts = new IBlockVoxelTexture[](7);
		bvts[0] = new DirtTexture;
		bvts[1] = new GrassTexture;
		bvts[2] = new SandTexture;
		bvts[3] = new StoneTexture;
		bvts[4] = new GlassTexture;
		bvts[5] = new WoodBarkTexture;
		bvts[6] = new WoodCoreTexture;
		BlockProcessor blockProcessor = new BlockProcessor(moxane, registry, bvts);
		registry.add(blockProcessor);

		registry.add(new Cube);
		registry.add(new Slope);
		registry.add(new Tetrahedron);
		registry.add(new AntiTetrahedron);
		registry.add(new HorizontalSlope);

		registry.add(new Dirt);
		registry.add(new Grass);
		registry.add(new Sand);
		registry.add(new Stone);

		registry.finaliseResources;

		TerrainSettings s = {
			addRange : Vector3i(3, 3, 3),
			extendedAddRange : Vector3i(5, 5, 5),
			removeRange : Vector3i(7, 7, 7),
			playerLocalRange : Vector3i(3, 3, 3),
			registry : registry,
			moxane : super.moxane
		};

		terrain = new TerrainEngine(s, Vector3f(0, 0.75f, 0));
		terrainRenderer = new TerrainRenderer(terrain);

		pipeline.physicalQueue ~= terrainRenderer;

		auto skySystem = new SkySystem(moxane);
		auto skyRenderer = new SkyRenderer7R24D(moxane, skySystem);
		/+{
		Texture2D sun = new Texture2D(AssetManager.translateToAbsoluteDir("content/textures/exp_sun.png"));
		Texture2D moon = new Texture2D(AssetManager.translateToAbsoluteDir("content/textures/exp_moon.png"));
		auto skyObjects = new SkyObjects(moxane, sun, moon);
		skyRenderer.objects = skyObjects;
		}+/
		auto skyEntity = createSkyEntity(em, Vector3f(0f, 0.75f, 0f), 80, 50, VirtualTime(17, 0, 0));
		em.add(skyEntity);
		pipeline.physicalQueue ~= skyRenderer;
		pipeline.fog.colour = skyRenderer.fogColour;
	}

	override void setToCurrent(Scene overwrote) {
	}

	override void removedCurrent(Scene overwroteBy) {
	}

	override void onUpdate() {
		client.update;
		terrain.update;
	}

	override void onRender() {
		pipeline.draw(camera);
	}
}