module squareone.client.scenes.game;

import squareone.client.terrain.basic.engine : TerrainEngine, TerrainSettings;
import squareone.client.terrain.basic.renderer;
import squareone.common.terrain.basic.packets;
import squareone.common.voxel;
import squareone.common.content.voxel.block;
import squareone.client.content.voxel.block;
import squareone.client.systems.sky;
import squareone.client.systems.time;
import squareone.client.content.entities.player;
import squareone.common.terrain.basic.picker;

import squareone.client.content.voxel.vegetation;

import moxane.core;
import moxane.graphics.redo;
import moxane.network;
import moxane.physics;
import moxane.io;

import dlib.math;

@safe:

final class Game : Scene
{
	private Pipeline pipeline;
	private Camera camera;

	private TerrainEngine terrain;
	private TerrainRenderer terrainRenderer;

	private EntityManager em;
	private PhysicsSystem physics;
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
		initPhysics;
		initTerrainEngine;
	}

	private void onLoginComplete(ref LoginVerificationPacket packet)
	{
		client.event(VoxelUpdate.technicalName).addCallback(&onVoxelUpdate);
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
		camera.position = Vector3f(-2, 52f, 0);
		camera.rotation = Vector3f(65, 90, 0);
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
		blockProcessor.physics = this.physics;
		registry.add(blockProcessor);

		registry.add(new Cube);
		registry.add(new Slope);
		registry.add(new Tetrahedron);
		registry.add(new AntiTetrahedron);
		registry.add(new HorizontalSlope);
		registry.add(new GrassMesh);

		registry.add(new Dirt);
		registry.add(new Grass);
		registry.add(new Sand);
		registry.add(new Stone);
		registry.add(new GrassBlade);

		IVegetationVoxelTexture[] vegetationTextures;
		vegetationTextures ~= new GrassBladeTexture;

		VegetationProcessor veggieProcessor = new VegetationProcessor(moxane, registry, vegetationTextures);
		registry.add(veggieProcessor);

		registry.finaliseResources;

		TerrainSettings s = {
			addRange : Vector3i(3, 3, 3),
			extendedAddRange : Vector3i(5, 5, 5),
			removeRange : Vector3i(7, 7, 7),
			playerLocalRange : Vector3i(3, 3, 3),
			registry : registry,
			moxane : super.moxane
		};

		terrain = new TerrainEngine(s, Vector3f(0, 52f, 0));
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
		auto skyEntity = createSkyEntity(em, Vector3f(0f, 52f, 0f), 80, 50, VirtualTime(17, 0, 0));
		em.add(skyEntity);
		pipeline.physicalQueue ~= skyRenderer;
		pipeline.fog.colour = skyRenderer.fogColour;
	}

	Entity playerEntity;

	void initPhysics()
	{
		physics = new PhysicsSystem(moxane.services.get!Log, em);
		physics.gravity = Vector3f(0, -9.81, 0);
		em.add(physics);

		InputManager im = moxane.services.get!InputManager;
		im.setBinding("playerWalkForward", Keys.w);
		im.setBinding("playerWalkBackward", Keys.s);
		im.setBinding("playerStrafeLeft", Keys.a);
		im.setBinding("playerStrafeRight", Keys.d);
		im.setBinding("debugUp", Keys.e);
		im.setBinding("debugDown", Keys.q);
		im.setBinding("invVoxelIncSize", Keys.equal);
		im.setBinding("invVoxelDecSize", Keys.minus);

		string[] playerKeyBindings = new string[](PlayerBindingName.length);
		playerKeyBindings[PlayerBindingName.walkForward] = "playerWalkForward";
		playerKeyBindings[PlayerBindingName.walkBackward] = "playerWalkBackward";
		playerKeyBindings[PlayerBindingName.strafeLeft] = "playerStrafeLeft";
		playerKeyBindings[PlayerBindingName.strafeRight] = "playerStrafeRight";
		playerKeyBindings[PlayerBindingName.debugUp] = "debugUp";
		playerKeyBindings[PlayerBindingName.debugDown] = "debugDown";
		playerEntity = createPlayer(em, 2f, 90f, -90f, 10f, playerKeyBindings, physics);
		PlayerComponent* pc = playerEntity.get!PlayerComponent;
		pc.camera = camera;
		pc.allowInput = true;
	}

	override void setToCurrent(Scene overwrote) {
	}

	override void removedCurrent(Scene overwroteBy) {
	}

	private bool clickPrev = false, placePrev = false;
	private bool keyCapture = false, f1Prev = false;
	private BlockPosition properBP, snappedBP;

	override void onUpdate() {
		Window win = moxane.services.get!Window;
		bool changeCapture = win.isKeyDown(Keys.f1) && !f1Prev;
		f1Prev = win.isKeyDown(Keys.f1);
		if(changeCapture)
		{
			keyCapture = !keyCapture;
		}
		win.hideCursor = keyCapture;

		bool shouldBreak = win.isMouseButtonDown(MouseButton.right) && !clickPrev;
		clickPrev = win.isMouseButtonDown(MouseButton.right);
		bool shouldPlace = win.isMouseButtonDown(MouseButton.left) && !placePrev;
		placePrev = win.isMouseButtonDown(MouseButton.left);

		PhysicsComponent* phys = playerEntity.get!PhysicsComponent;
		DynamicPlayerBodyMT dpb = cast(DynamicPlayerBodyMT)phys.rigidBody;
		if(!keyCapture)
		{
			phys.rigidBody.transform.position = Vector3f(0, 52, 0);
			(cast(DynamicPlayerBodyMT)phys.rigidBody).velocity = Vector3f(0, 0, 0);
		}

		if(keyCapture)
		{
			PlayerComponent* pc = playerEntity.get!PlayerComponent;

			PickerIgnore pickerIgnore = PickerIgnore([0], [0]);
			PickResult pr = pick(pc.camera.position, pc.camera.rotation, terrain.voxelInteraction, 10, pickerIgnore);
			if(pr.got) 
			{
				properBP = pr.blockPosition;

				if(shouldBreak || shouldPlace)
				{
					if(shouldPlace)
					{
						if(pr.side == VoxelSide.nx) pr.blockPosition.x -= 1;
						if(pr.side == VoxelSide.px) pr.blockPosition.x += 1;
						if(pr.side == VoxelSide.ny) pr.blockPosition.y -= 1;
						if(pr.side == VoxelSide.py) pr.blockPosition.y += 1;
						if(pr.side == VoxelSide.nz) pr.blockPosition.z -= 1;
						if(pr.side == VoxelSide.pz) pr.blockPosition.z += 1;
					}

					VoxelUpdate u;
					u.updated = Voxel(2, 1, 0, 0);
					u.x = cast(int)pr.blockPosition.x;
					u.y = cast(int)pr.blockPosition.y;
					u.z = cast(int)pr.blockPosition.z;
					client.send(u);

					import std.stdio;
					writeln("voxelupdate");

					//terrainManager.voxelInteraction.set(shouldPlace ? Voxel(7, 1, 0, 0) : Voxel(), pr.blockPosition + BlockPosition(x, y, z));
				}
			}
		}


		client.update;
		terrain.update;
	}

	override void onRender() {
		pipeline.draw(camera);
	}
}