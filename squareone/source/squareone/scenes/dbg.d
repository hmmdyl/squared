module squareone.scenes.dbg;

import moxane.core;
import moxane.io;
import moxane.graphics.renderer;
import moxane.graphics.firstperson;
import moxane.graphics.sprite;
import moxane.graphics.postprocess;
import moxane.graphics.postprocesses.fog;
import moxane.graphics.light;
import moxane.graphics.transformation;
import moxane.graphics.imgui;

import squareone.terrain.basic.manager;
import squareone.voxel;
import squareone.voxelcontent.block;
import squareone.voxelcontent.fluid.processor;
import squareone.voxelcontent.vegetation;
import squareone.voxelcontent.glass;
import squareone.systems.sky;
import squareone.systems.gametime;
import squareone.entities.player;
import squareone.systems.inventory;

import dlib.math;

import core.stdc.stdio : sprintf;

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

	private PlayerInventorySystem playerInventory;

	private FirstPersonCamera camera;
	private SpriteFont font;
	
	private Entity playerEntity;

	PointLight pl;

	private void initialise()
	{
		ImguiRenderer imgui = moxane.services.get!ImguiRenderer;
		if(imgui !is null)
			imgui.renderables ~= new SceneDebugAttachment(this);

		fog = new Fog(moxane, moxane.services.get!Renderer().postProcesses.common);
		Renderer renderer = moxane.services.get!Renderer();

		renderer.postProcesses.processes ~= fog;
		fog.update(Vector3f(0.9f, 0.9f, 0.95f), 0.029455f, 10f, Matrix4f.identity);
		pl = new PointLight;
		pl.ambientIntensity = 0f;
		pl.diffuseIntensity = 120f;
		pl.colour = Vector3f(1f, 1f, 1f);
		pl.position = Vector3f(-2f, 4f, 0f);
		pl.constAtt = 1f;
		pl.linAtt = 0.9f;
		pl.expAtt = 0.1f;
		renderer.lights.pointLights ~= pl;

		skySystem = new SkySystem(moxane);
		skyRenderer = new SkyRenderer7R24D(moxane, skySystem);
		renderer.addSceneRenderable(skyRenderer);
		skyAttachment = new SkyRenderer7R24D.DebugAttachment(skyRenderer, moxane);
		imgui.renderables ~= skyAttachment;

		EntityManager em = moxane.services.get!EntityManager;

		skyEntity = createSkyEntity(em, Vector3f(0f, 0f, 0f), 50, 80, VirtualTime.init);
		em.add(skyEntity);

		resources = new Resources;
		resources.add(new Invisible);
		resources.add(new Air);

		IBlockVoxelTexture[] bvts = new IBlockVoxelTexture[](5);
		bvts[0] = new DirtTexture;
		bvts[1] = new GrassTexture;
		bvts[2] = new SandTexture;
		bvts[3] = new StoneTexture;
		bvts[4] = new GlassTexture;

		IVegetationVoxelTexture[] vvts;
		vvts ~= new GrassBladeTexture;

		blockProcessor = new BlockProcessor(moxane, bvts);
		resources.add(blockProcessor);
		fluidProcessor = new FluidProcessor(moxane, [resources.getMesh(Invisible.technicalStatic)]);
		resources.add(fluidProcessor);
		veggieProcessor = new VegetationProcessor(moxane, vvts);
		resources.add(veggieProcessor);
		glassProcessor = new GlassProcessor(moxane, blockProcessor);
		resources.add(glassProcessor);

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

		resources.finaliseResources;
		BasicTMSettings settings = BasicTMSettings(Vector3i(8, 8, 8), Vector3i(10, 10, 10), Vector3i(12, 12, 12), resources);
		terrainManager = new BasicTerrainManager(moxane, settings);
		terrainRenderer = new BasicTerrainRenderer(terrainManager);

		//Renderer renderer = moxane.services.get!Renderer;
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

		string[] playerKeyBindings = new string[](PlayerBindingName.length);
		playerKeyBindings[PlayerBindingName.walkForward] = "playerWalkForward";
		playerKeyBindings[PlayerBindingName.walkBackward] = "playerWalkBackward";
		playerKeyBindings[PlayerBindingName.strafeLeft] = "playerStrafeLeft";
		playerKeyBindings[PlayerBindingName.strafeRight] = "playerStrafeRight";
		playerKeyBindings[PlayerBindingName.debugUp] = "debugUp";
		playerKeyBindings[PlayerBindingName.debugDown] = "debugDown";
		playerEntity = createPlayer(em, 2f, 90f, -90f, 10f, playerKeyBindings);
		PlayerComponent* pc = playerEntity.get!PlayerComponent;
		pc.camera = camera;
		pc.allowInput = true;

		playerInventory = new PlayerInventorySystem(moxane, renderer, null);
		PlayerInventory* pi = playerEntity.createComponent!PlayerInventory;
		PlayerInventoryLocal* pil = playerEntity.createComponent!PlayerInventoryLocal;
		pil.isOpen = false;
		renderer.uiRenderables ~= playerInventory;
		playerInventory.target = playerEntity;
	}

	private void setCamera(Vector2i size)
	{
		Renderer renderer = moxane.services.get!Renderer;

		camera.width = cast(uint)size.x;
		camera.height = cast(uint)size.y;
		camera.perspective.fieldOfView = 75f;
		camera.perspective.near = 0.1f;
		camera.perspective.far = 100f;
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

	private Vector2d prevCursor = Vector2d(0, 0);

	private char[1024] buffer;

	private bool clickPrev = false;

	override void onUpdate() @trusted
	{
		Window win = moxane.services.get!Window;

		Transform* t = playerEntity.get!Transform;
		pl.position = t.position;
		pl.position.y += 30f;
		pl.position.x -= 3f;
		pl.position.z -= 3f;
		{
			Transform* sk = skyEntity.get!Transform;
			sk.position = t.position;
		}

		if(win.isFocused && win.isMouseButtonDown(MouseButton.right))
		{
			win.hideCursor = true;
			clickPrev = false;
		}
		else if(win.isFocused && win.isKeyDown(Keys.tab) && win.isMouseButtonDown(MouseButton.left) && !clickPrev)
		{
			PlayerComponent* pc = playerEntity.get!PlayerComponent;
			//if(pc is null) break;

			import squareone.voxelutils.picker;
			PickerIgnore pickerIgnore = PickerIgnore([0], [0]);
			PickResult pr = pick(pc.camera.position, pc.camera.rotation, terrainManager, 10, pickerIgnore);
			if(pr.got) 
				terrainManager.voxelInteraction.set(Voxel(), pr.blockPosition);

			clickPrev = true;
		}
		else 
		{
			win.hideCursor = false;
			clickPrev = false;
		}

		fog.sceneView = camera.viewMatrix;

		terrainManager.cameraPosition = camera.position;
		terrainManager.update;

		/*buffer[] = char.init;
		int l = sprintf(buffer.ptr, 
"Camera position: %0.3f %0.3f %0.3f
Camera rotation: %0.3f %0.3f %0.3f
						
Delta: %0.6fs
						
Chunks: %d", 
						camera.position.x, camera.position.y, camera.position.z,
						camera.rotation.x, camera.rotation.y, camera.rotation.z,
						moxane.deltaTime,
						terrainManager.numChunks);
		moxane.services.get!SpriteRenderer().drawText(cast(string)buffer[0..l], font, Vector2i(0, 10));*/
	}

	override void onRenderBegin() @trusted
	{
		super.onRenderBegin;

		Window win = moxane.services.get!Window;
		import derelict.opengl3.gl3;
		moxane.services.get!Renderer().wireframe = win.isKeyDown(Keys.x);
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
			igText("Delta: %0.3fms", scene.moxane.deltaTime * 1000f);
			igText("Frames: %d", scene.moxane.frames);
		}
		if(igCollapsingHeader("Terrain", ImGuiTreeNodeFlags_DefaultOpen))
		{
			igText("Chunks: %d", scene.terrainManager.numChunks);
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
		igSliderFloat("Gradient", &scene.fog.gradient, 8f, 18f, "%.3f");

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