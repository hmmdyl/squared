module squareone.scenes.redo;

import squareone.voxel;
import squareone.terrain.basic.manager;
import squareone.content.voxel.block;
import squareone.systems.sky;
import squareone.systems.gametime;

import moxane.core;
import moxane.graphics.redo;

import dlib.math;

final class RedoScene : Scene 
{
	Pipeline pipeline;
	Camera camera;

	Entity skyEntity;

	Resources resources;
	BlockProcessor blockProcessor;
	BasicTerrainManager terrainManager;
	TerrainRenderer terrainRenderer;

	this(Moxane moxane, SceneManager manager, Scene parent = null)
		in { assert(moxane !is null); assert(manager !is null); assert(parent is null); }
	do {
		super(moxane, manager, parent);
		
		pipeline = new Pipeline(moxane, this);
		camera = new Camera;
		camera.perspective.fieldOfView = 75f;
		camera.perspective.near = 0.1f;
		camera.perspective.far = 600f;
		camera.width = cast(uint)pipeline.window.framebufferSize.x;
		camera.height = cast(uint)pipeline.window.framebufferSize.y;
		camera.isOrtho = false;
		camera.position = Vector3f(0, 52, 0);
		camera.rotation = Vector3f(5, 90, 0);
		camera.buildProjection;
		camera.buildView;

		resources = new Resources;
		resources.add(new Invisible);
		resources.add(new Air);

		IBlockVoxelTexture[] bvts = new IBlockVoxelTexture[](7);
		bvts[0] = new DirtTexture;
		bvts[1] = new GrassTexture;
		bvts[2] = new SandTexture;
		bvts[3] = new StoneTexture;
		bvts[4] = new GlassTexture;
		bvts[5] = new WoodBarkTexture;
		bvts[6] = new WoodCoreTexture;
		blockProcessor = new BlockProcessor(moxane, bvts);
		resources.add(blockProcessor);

		resources.add(new Cube);
		resources.add(new Slope);
		resources.add(new Tetrahedron);
		resources.add(new AntiTetrahedron);
		resources.add(new HorizontalSlope);

		resources.add(new Dirt);
		resources.add(new Grass);
		resources.add(new Sand);
		resources.add(new Stone);

		resources.finaliseResources;
		enum immediate = 3;
		enum extended = 5;
		enum remove = extended + 2;
		enum local = 3;
		BasicTMSettings settings = BasicTMSettings(Vector3i(immediate, immediate, immediate), Vector3i(extended, immediate, extended), Vector3i(remove, immediate+2, remove), Vector3i(local, local, local), resources);
		terrainManager = new BasicTerrainManager(moxane, settings);
		terrainManager.cameraPosition = Vector3f(0, 52, 0);
		terrainRenderer = new TerrainRenderer(terrainManager);

		pipeline.physicalQueue ~= terrainRenderer;

		auto em = moxane.services.get!EntityManager;
		auto skySystem = new SkySystem(moxane);
		auto skyRenderer = new SkyRenderer7R24D(moxane, skySystem);
		/+{
			Texture2D sun = new Texture2D(AssetManager.translateToAbsoluteDir("content/textures/exp_sun.png"));
			Texture2D moon = new Texture2D(AssetManager.translateToAbsoluteDir("content/textures/exp_moon.png"));
			auto skyObjects = new SkyObjects(moxane, sun, moon);
			skyRenderer.objects = skyObjects;
		}+/
		skyEntity = createSkyEntity(em, Vector3f(0f, 50f, 0f), 80, 50, VirtualTime(17, 0, 0));
		em.add(skyEntity);

		pipeline.physicalQueue ~= skyRenderer;

		pipeline.fog.colour = skyRenderer.fogColour;
	}

	override void setToCurrent(Scene overwrote) {
	}

	override void removedCurrent(Scene overwroteBy) {
	}

	override void onUpdate() @trusted {
		terrainManager.update;
	}

	override void onRender() {
		pipeline.draw(camera);
	}

}