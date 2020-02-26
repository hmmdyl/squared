module squareone.scenes.dbg;

import moxane.core;
import moxane.io;
import moxane.graphics.renderer;
import moxane.graphics.ecs;
import moxane.graphics.firstperson;
import moxane.graphics.standard;
import moxane.graphics.sprite;
import moxane.graphics.postprocess;
import moxane.graphics.postprocesses.fog;
import moxane.graphics.light;
import moxane.graphics.imgui;
import moxane.graphics.texture;
import moxane.graphics.assimp;
import moxane.ui;
import moxane.physics;

import squareone.terrain.basic.manager;
import squareone.voxel;
import squareone.content.voxel.block;
import squareone.content.voxel.fluid.processor;
import squareone.content.voxel.vegetation;
import squareone.content.voxel.glass;
import squareone.systems.sky;
import squareone.systems.gametime;
import squareone.entities.player;
import squareone.systems.inventory2;
import squareone.content.item.test;

import dlib.math;

import core.stdc.stdio : sprintf;
import std.datetime.stopwatch;

final class DebugGameScene : Scene
{
	this(Moxane moxane, SceneManager manager, Scene parent = null)
	{
		super(moxane, manager, parent);

		initialise;
	}

	~this()
	{
	}

	private Resources resources;
	private BlockProcessor blockProcessor;
	private FluidProcessor fluidProcessor;
	private VegetationProcessor veggieProcessor;
	private GlassProcessor glassProcessor;
	private BasicTerrainRenderer terrainRenderer;
	private BasicTerrainManager terrainManager;

	private TimeSystem timeSystem;
	private SkySystem skySystem;
	private SkyRenderer7R24D skyRenderer;
	private SkyRenderer7R24D.DebugAttachment skyAttachment;
	private Entity skyEntity;
	private Fog fog;

	//private PlayerInventorySystem playerInventory;

	private FirstPersonCamera camera;
	private SpriteFont font;
	
	private Entity playerEntity;

	private Material blockSelectMaterial;
	private Entity blockSelector;

	PointLight pl;
	DirectionalLight dl;

	Renderer renderer;

	Entity crosshair;
	Entity physicsTest;

	PhysicsSystem physicsSystem;
	Material material;
	Vector3f[] verts, normals;

	private void initialise()
	{
		ImguiRenderer imgui = moxane.services.get!ImguiRenderer;
		if(imgui !is null)
			imgui.renderables ~= new SceneDebugAttachment(this);

		fog = new Fog(moxane, moxane.services.get!Renderer().postProcesses.common);
		renderer = moxane.services.get!Renderer();

		renderer.postProcesses.processes ~= fog;
		fog.update(Vector3f(1f, 1f, 1f), 0.022892f, 2.819f, Matrix4f.identity);
		pl = new PointLight;
		pl.ambientIntensity = 0f;
		pl.diffuseIntensity = 1f;
		pl.colour = Vector3f(1f, 1f, 1f);
		pl.position = Vector3f(-2f, 4f, 0f);
		pl.constAtt = 1f;
		pl.linAtt = 0.9f;
		pl.expAtt = 0.1f;
		renderer.lights.pointLights ~= pl;

		dl = new DirectionalLight;
		dl.ambientIntensity = 0.1f;
		dl.diffuseIntensity = 0.5f;
		dl.colour = Vector3f(1, 1, 1);
		dl.direction = Vector3f(0, 0.5, 0.5);
		renderer.lights.directionalLights ~= dl;

		skySystem = new SkySystem(moxane);
		skyRenderer = new SkyRenderer7R24D(moxane, skySystem);
		renderer.addSceneRenderable(skyRenderer);
		skyAttachment = new SkyRenderer7R24D.DebugAttachment(skyRenderer, moxane);
		imgui.renderables ~= skyAttachment;

		EntityManager em = moxane.services.get!EntityManager;

		skyEntity = createSkyEntity(em, Vector3f(0f, 0f, 0f), 24 * 8, 80, VirtualTime.init);
		em.add(skyEntity);

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

		IVegetationVoxelTexture[] vvts;
		vvts ~= new GrassBladeTexture;

		blockProcessor = new BlockProcessor(moxane, bvts);
		resources.add(blockProcessor);
		fluidProcessor = new FluidProcessor(moxane, [resources.getMesh(Invisible.technicalStatic)]);
		resources.add(fluidProcessor);
		veggieProcessor = new VegetationProcessor(moxane, vvts);
		resources.add(veggieProcessor);

		FluidProcessorDebugAttachment fluidDA = new FluidProcessorDebugAttachment(fluidProcessor);
		imgui.renderables ~= fluidDA;

		resources.add(new Cube);
		resources.add(new Slope);
		resources.add(new Tetrahedron);
		resources.add(new AntiTetrahedron);
		resources.add(new HorizontalSlope);
		resources.add(new FluidMesh);
		resources.add(new GrassMesh);
		resources.add(new LeafMesh);
		resources.add(new GlassMesh);

		resources.add(new Dirt);
		resources.add(new Grass);
		resources.add(new GrassBlade);
		resources.add(new Sand);
		resources.add(new Stone);
		resources.add(new GlassMaterial);
		resources.add(new WoodBark);
		resources.add(new WoodCore);

		resources.finaliseResources;
		enum immediate = 3;
		enum extended = 5;
		enum remove = extended + 2;
		enum local = 3;
		BasicTMSettings settings = BasicTMSettings(Vector3i(immediate, immediate, immediate), Vector3i(extended, immediate, extended), Vector3i(remove, immediate+2, remove), Vector3i(local, local, local), resources);
		terrainManager = new BasicTerrainManager(moxane, settings);
		terrainRenderer = new BasicTerrainRenderer(terrainManager);

		renderer.addSceneRenderable(terrainRenderer);

		Window win = moxane.services.get!Window;

		camera = new FirstPersonCamera;
		setCamera(win.size);
		camera.position = Vector3f(0f, 0f, 0f);
		camera.rotation = Vector3f(0f, 0f, 0f);
		camera.buildView;
		renderer.primaryCamera = camera;

		win.onFramebufferResize.add((win, size) @trusted {
			setCamera(size);
		});

		SpriteRenderer spriteRenderer = moxane.services.get!SpriteRenderer;
		font = spriteRenderer.createFont(AssetManager.translateToAbsoluteDir("content/moxane/font/MODES___.ttf"), 48);

		InputManager im = moxane.services.get!InputManager;
		im.setBinding("playerWalkForward", Keys.w);
		im.setBinding("playerWalkBackward", Keys.s);
		im.setBinding("playerStrafeLeft", Keys.a);
		im.setBinding("playerStrafeRight", Keys.d);
		im.setBinding("debugUp", Keys.e);
		im.setBinding("debugDown", Keys.q);
		im.setBinding("invVoxelIncSize", Keys.equal);
		im.setBinding("invVoxelDecSize", Keys.minus);

		physicsSystem = new PhysicsSystem(moxane, em);
		physicsSystem.gravity = Vector3f(0, -9.81, 0);
		em.add(physicsSystem);
		moxane.services.register!PhysicsSystem(physicsSystem);

		string[] playerKeyBindings = new string[](PlayerBindingName.length);
		playerKeyBindings[PlayerBindingName.walkForward] = "playerWalkForward";
		playerKeyBindings[PlayerBindingName.walkBackward] = "playerWalkBackward";
		playerKeyBindings[PlayerBindingName.strafeLeft] = "playerStrafeLeft";
		playerKeyBindings[PlayerBindingName.strafeRight] = "playerStrafeRight";
		playerKeyBindings[PlayerBindingName.debugUp] = "debugUp";
		playerKeyBindings[PlayerBindingName.debugDown] = "debugDown";
		playerEntity = createPlayer(em, 2f, 90f, -90f, 10f, playerKeyBindings, physicsSystem);
		PlayerComponent* pc = playerEntity.get!PlayerComponent;
		pc.camera = camera;
		pc.allowInput = true;

		/+playerInventory = new PlayerInventorySystem(moxane, renderer, em);
		em.add(playerInventory);
		PlayerInventory* pi = playerEntity.createComponent!PlayerInventory;
		PlayerInventoryLocal* pil = playerEntity.createComponent!PlayerInventoryLocal;
		pil.isOpen = false;
		renderer.uiRenderables ~= new PlayerInventoryRenderer(playerInventory);+/
		//playerInventory.target = playerEntity;

		crosshair = new Entity(em);
		Transform* crosshairT = crosshair.createComponent!Transform;
		*crosshairT = Transform.init;
		UIPicture* crosshairPic = crosshair.createComponent!UIPicture;
		crosshairPic.offset = win.framebufferSize / 2 - 32;
		crosshairPic.dimensions = Vector2i(33, 33);
		crosshairPic.texture = new Texture2D(AssetManager.translateToAbsoluteDir("content/textures/crosshair_3.png"), Texture2D.ConstructionInfo.standard);
	
		em.add(crosshair);

		auto sr = moxane.services.get!StandardRenderer;

		material = new Material(sr.standardMaterialGroup);
		material.diffuse = Vector3f(1f, 0.5f, 0.9f);
		material.specular = Vector3f(0f, 0f, 0f);
		material.normal = null;
		material.depthWrite = true;
		material.hasLighting = true;
		material.castsShadow = true;

		{
			blockSelectMaterial = new Material(sr.standardMaterialGroup);
			with(blockSelectMaterial)
			{
				diffuse = Vector3f(0.9f, 0f, 0f);
				specular = Vector3f(0, 0, 0);
				normal = null;
				depthWrite = false;
				hasLighting = false;
				castsShadow = false;
			}

			Vector3f[] vertices = [
				Vector3f(0, 0, 0), Vector3f(1, 0, 0),
				Vector3f(1, 0, 0), Vector3f(1, 0, 1),
				Vector3f(1, 0, 1), Vector3f(0, 0, 1),
				Vector3f(0, 0, 1), Vector3f(0, 0, 0),

				Vector3f(0, 0, 0), Vector3f(0, 1, 0),
				Vector3f(1, 0, 0), Vector3f(1, 1, 0),
				Vector3f(1, 0, 1), Vector3f(1, 1, 1),
				Vector3f(0, 0, 1), Vector3f(0, 1, 1),

				Vector3f(0, 1, 0), Vector3f(1, 1, 0),
				Vector3f(1, 1, 0), Vector3f(1, 1, 1),
				Vector3f(1, 1, 1), Vector3f(0, 1, 1),
				Vector3f(0, 1, 1), Vector3f(0, 1, 0),
			];
			Vector3f[] normals = new Vector3f[](vertices.length);
			normals[] = Vector3f(0, 0, 0);
			StaticModel sm = new StaticModel(sr, blockSelectMaterial, vertices, normals, null, PrimitiveType.lines);
			sm.localTransform = Transform.init;
			sm.renderConfig = LinesConfig(12f);

			blockSelector = new Entity(em);
			em.add(blockSelector);
			Transform* t = blockSelector.createComponent!Transform;
			*t = Transform.init;
			EntityRenderSystem ers = moxane.services.get!EntityRenderSystem;
			RenderComponent* r = blockSelector.createComponent!RenderComponent;
			ers.addModel(sm, *r);
		}

		import std.experimental.allocator.gc_allocator;
		loadMesh!(Vector3f, Vector3f, GCAllocator)(AssetManager.translateToAbsoluteDir("content/models/skySphere.dae"), verts, normals);
	
        InventorySystem inven = new InventorySystem(moxane, em);
        em.add(inven);
        createTestPlayer(em);

		InventoryRenderer invenRenderer = new InventoryRenderer(moxane, inven, renderer.gl, renderer);
		renderer.uiRenderables ~= invenRenderer;
    }

	private void setCamera(Vector2i size)
	{
		Renderer renderer = moxane.services.get!Renderer;

		camera.width = cast(uint)size.x;
		camera.height = cast(uint)size.y;
		camera.perspective.fieldOfView = 75f;
		camera.perspective.near = 0.01f;
		camera.perspective.far = 200f;
		camera.buildProjection;
		
		renderer.uiCamera.width = cast(uint)size.x;
		renderer.uiCamera.height = cast(uint)size.y;
		renderer.uiCamera.deduceOrtho;
		renderer.uiCamera.buildProjection;

		renderer.cameraUpdated;
	}

	override void setToCurrent(Scene overwrote) 
	{}

	override void removedCurrent(Scene overwroteBy)
	{}

	PhysicsComponent* phys;

	/+private void addPhysicsTest(Vector3f pos = playerEntity.get!Transform().position + Vector3f(0, 7, 0))
	{
		auto sr = moxane.services.get!StandardRenderer;
		StaticModel sm = new StaticModel(sr, material, verts, normals);
		sm.localTransform = Transform.init;

		auto em = moxane.services.get!EntityManager;
		auto ers = moxane.services.get!EntityRenderSystem;

		Entity pt = new Entity(em);
		em.add(pt);
		Transform* transform = pt.createComponent!Transform;
		*transform = Transform.init;
		transform.position = pos;
		RenderComponent* rc = pt.createComponent!RenderComponent;
		ers.addModel(sm, *rc);

		/+PhysicsComponent*+/ phys = pt.createComponent!PhysicsComponent;
		Collider box = //new BoxCollider(physicsSystem, Vector3f(1, 1, 1));
			new SphereCollider(physicsSystem, 1);
		BodyMT body_ = new BodyMT(physicsSystem, BodyMT.Mode.dynamic, box, AtomicTransform(*transform));
		body_.gravity = true;
		body_.mass = 1f;
		body_.massMatrix = Vector3f(1, 1, 1);
		phys.collider = box;
		phys.rigidBody = body_;
	}+/

	private Vector2d prevCursor = Vector2d(0, 0);

	//private char[1024] buffer;

	private bool clickPrev = false, placePrev = false;
	private bool keyCapture = false, f1Prev = false;
	private float managementTime;
	private BlockPosition properBP, snappedBP;

	private int toolSize = 4;
	private bool incPrev = false, decPrev = false;

	override void onUpdate() @trusted
	{
		Window win = moxane.services.get!Window;
		InputManager im = moxane.services.get!InputManager;

		Transform* t = playerEntity.get!Transform;
		pl.position = t.position;
		{
			Transform* sk = skyEntity.get!Transform;
			sk.position = t.position;
		}

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

		bool incKeyState = im.getBindingState("invVoxelIncSize") == ButtonAction.press;
		bool shouldInc = incKeyState && !incPrev;
		incPrev = incKeyState;
		bool decKeyState = im.getBindingState("invVoxelDecSize") == ButtonAction.press;
		bool shouldDec = decKeyState && !decPrev;
		decPrev = decKeyState;

		if(shouldInc) toolSize *= 2;
		if(shouldDec) toolSize /= 2;

		if(toolSize < 1) toolSize = 1;
		if(toolSize > 1) toolSize = 1;

		PhysicsComponent* phys = playerEntity.get!PhysicsComponent;
		DynamicPlayerBodyMT dpb = cast(DynamicPlayerBodyMT)phys.rigidBody;

		if(!keyCapture)
		{
			phys.rigidBody.transform.position = Vector3f(0, 10, 0);
			(cast(DynamicPlayerBodyMT)phys.rigidBody).velocity = Vector3f(0, 0, 0);
		}
		//else phys.rigidBody.freeze = false;

		if(keyCapture)
		{
			PlayerComponent* pc = playerEntity.get!PlayerComponent;

			import squareone.terrain.basic.picker;
			PickerIgnore pickerIgnore = PickerIgnore([0], [0]);
			PickResult pr = pick(pc.camera.position, pc.camera.rotation, terrainManager, 10, pickerIgnore);
			if(pr.got) 
			{
				properBP = pr.blockPosition;

				blockSelector.get!Transform().position = ChunkPosition.blockPosRealCoord(pr.blockPosition);
				blockSelector.get!Transform().scale = Vector3f(ChunkData.voxelScale * toolSize, ChunkData.voxelScale * toolSize, ChunkData.voxelScale * toolSize);

				if(shouldBreak || shouldPlace)
				{
					if(shouldPlace)
					{
						if(pr.side == VoxelSide.nx) pr.blockPosition.x -= toolSize;
						if(pr.side == VoxelSide.px) pr.blockPosition.x += toolSize;
						if(pr.side == VoxelSide.ny) pr.blockPosition.y -= toolSize;
						if(pr.side == VoxelSide.py) pr.blockPosition.y += toolSize;
						if(pr.side == VoxelSide.nz) pr.blockPosition.z -= toolSize;
						if(pr.side == VoxelSide.pz) pr.blockPosition.z += toolSize;
					}

					foreach(x; 0 .. toolSize)
						foreach(y; 0 .. toolSize)
							foreach(z; 0 .. toolSize)
								terrainManager.voxelInteraction.set(shouldPlace ? Voxel(7, 1, 0, 0) : Voxel(), pr.blockPosition + BlockPosition(x, y, z));
				}
			}
		}

		fog.sceneView = camera.viewMatrix;

		StopWatch sw = StopWatch(AutoStart.yes);
		terrainManager.cameraPosition = camera.position;
		terrainManager.update;
		sw.stop;
		managementTime = sw.peek.total!"nsecs" / 1_000_000f;

		terrainRenderer.renderTime = 0f;
	}

	override void onRenderBegin() @trusted
	{
		super.onRenderBegin;

		Window win = moxane.services.get!Window;
		import derelict.opengl3.gl3;
		moxane.services.get!Renderer().wireframe = win.isKeyDown(Keys.x);

		terrainRenderer.drawCallsPhys = 0;
		terrainRenderer.drawCallsRefrac = 0;
	}

	override void onRender()
	{}
}

private final class SceneDebugAttachment : IImguiRenderable
{
	DebugGameScene scene;
	this(DebugGameScene scene) { this.scene = scene; }

	void game()
	{
		import cimgui;

		igBegin("Scene status");
		scope(exit) igEnd();

		if(igCollapsingHeader("Camera & Engine", ImGuiTreeNodeFlags_DefaultOpen))
		{
			igText("Position: %0.3f, %0.3f, %0.3f", scene.camera.position.x, scene.camera.position.y, scene.camera.position.z);
			igText("Rotation: %0.3f, %0.3f, %0.3f", scene.camera.rotation.x, scene.camera.rotation.y, scene.camera.rotation.z);
			igText("Delta: %7.3fms", scene.moxane.deltaTime * 1000f);
			igText("Frames: %d", scene.moxane.frames);
			igText("Physics delta: %7.3fms", scene.physicsSystem.deltaTime * 1000f);
			igText("Size: %dx%d", scene.camera.width, scene.camera.height);
			
			auto playerRb = cast(DynamicPlayerBodyMT)scene.playerEntity.get!PhysicsComponent().rigidBody;
			Vector3f pp = playerRb.transform.position;
			igText("Player phys pos: %f %f %f", pp.x, pp.y, pp.z);
			igText("Velocity: %f %f %f", playerRb.velocity.x, playerRb.velocity.y, playerRb.velocity.z);
			igText("Foot hit: %d | Dir hit: %d", playerRb.onFoot, playerRb.onFront);

			igSliderFloat("Min bias", &scene.renderer.lights.biasSmall, 0f, 0.01f, "%.9f");
			igSliderFloat("Max bias", &scene.renderer.lights.biasLarge, 0f, 0.02f, "%.9f");
		}
		if(igCollapsingHeader("Lights", 0))
		{
			igColorPicker3("Directional light colour", scene.dl.colour.arrayof);
			igColorPicker3("Point light colour", scene.pl.colour.arrayof);
		}
		if(igCollapsingHeader("Terrain", ImGuiTreeNodeFlags_DefaultOpen))
		{
			igText("Chunks: %d", scene.terrainManager.numChunks);
			igText("Created: %d", scene.terrainManager.chunksCreated);
			igText("Hibernated: %d", scene.terrainManager.chunksHibernated);
			igText("Removed: %d", scene.terrainManager.chunksRemoved);
			igText("Compressed: %d", scene.terrainManager.chunksCompressed);
			igText("Decompressed: %d", scene.terrainManager.chunksDecompressed);
			igText("Noise completed: %d", scene.terrainManager.noiseCompleted);
			igText("Noise completed last second: %d", scene.terrainManager.noiseCompletedSecond);
			igText("Meshes ordered: %d", scene.terrainManager.meshOrders);
			igText("Manage time: %6.3fms", scene.managementTime);

			int ci = cast(int)scene.terrainRenderer.culling;
			igComboStr("Cull Mode", &ci, "None\0All", -1);
			scene.terrainRenderer.culling = cast(bool)ci;

			igText("Render time: %7.3fms", scene.terrainRenderer.renderTime * 1000f);
			igText("Render prepare time: %7.3fms", scene.terrainRenderer.prepareTime * 1000f);

			igText("Draw calls phys.: %d", scene.terrainRenderer.drawCallsPhys);
			igText("Draw calls refrac.: %d", scene.terrainRenderer.drawCallsRefrac);

			igText("Block pos: %d, %d, %d", scene.properBP.x, scene.properBP.y, scene.properBP.z);
			igText("Block pos snapped: %d, %d, %d", scene.snappedBP.x, scene.snappedBP.y, scene.snappedBP.z);
		}
		if(igCollapsingHeader("Time", ImGuiTreeNodeFlags_DefaultOpen))
		{
			SkyComponent* sky = scene.skyEntity.get!SkyComponent;
			igText("Time: %d:%d:%d, %f", sky.time.hour, sky.time.minute, sky.time.second, sky.time.decimal);
			igText("Increment");
			igSameLine();
			if(igButton("HOUR", ImVec2(0, 0)))
			   sky.time.incHour;
			igSameLine();
			if(igButton("MINUTE", ImVec2(0, 0)))
				sky.time.incMinute;
			igSameLine();
			if(igButton("SECOND", ImVec2(0, 0)))
				sky.time.incSecond;
		}
	}

	void fog()
	{
		import cimgui;
		igBegin("Fog");

		igSliderFloat("Density", &scene.fog.density, 0f, 0.1f, "%.6f");
		igSliderFloat("Gradient", &scene.fog.gradient, 0f, 18f, "%.3f");

		float[3] col = scene.fog.colour.arrayof;
		igColorPicker3("Fog Colour", col);
		scene.fog.colour.arrayof = col;
		igEnd();
	}

	void renderUI(ImguiRenderer imgui, Renderer renderer, ref LocalContext lc)
	{
		game;
		fog;
	}
}