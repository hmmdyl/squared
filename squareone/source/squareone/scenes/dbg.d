module squareone.scenes.dbg;

import moxane.core;
import moxane.io;
import moxane.graphics.renderer;
import moxane.graphics.firstperson;
import moxane.graphics.sprite;
import moxane.graphics.postprocess;
import moxane.graphics.postprocesses.fog;
import moxane.graphics.light;
import moxane.graphics.imgui;

import squareone.terrain.basic.manager;
import squareone.voxel;
import squareone.voxelcontent.block;
import squareone.voxelcontent.fluid.processor;
import squareone.voxelcontent.vegetation;

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
	private BasicTerrainRenderer terrainRenderer;
	private BasicTerrainManager terrainManager;

	private Fog fog;

	private FirstPersonCamera camera;
	private SpriteFont font;

	private void initialise()
	{
		ImguiRenderer imgui = moxane.services.get!ImguiRenderer;
		if(imgui !is null)
			imgui.renderables ~= new SceneDebugAttachment(this);

		fog = new Fog(moxane, moxane.services.get!Renderer().postProcesses.common);
		Renderer renderer = moxane.services.get!Renderer();
		renderer.postProcesses.processes ~= fog;
		fog.update(Vector3f(0.9f, 0.9f, 0.95f), 0.029455f, 10f, Matrix4f.identity);
		PointLight pl;
		pl.ambientIntensity = 0f;
		pl.diffuseIntensity = 10f;
		pl.colour = Vector3f(0.1f, 0.7f, 1f);
		pl.position = Vector3f(0f, 2f, 0f);
		pl.constAtt = 0f;
		pl.linAtt = 0.2f;
		pl.expAtt = 0.9f;
		renderer.lights.pointLights ~= pl;

		resources = new Resources;
		resources.add(new Invisible);
		resources.add(new Air);

		IBlockVoxelTexture[] bvts = new IBlockVoxelTexture[](2);
		bvts[0] = new DirtTexture;
		bvts[1] = new GrassTexture;

		IVegetationVoxelTexture[] vvts;
		vvts ~= new GrassBladeTexture;

		blockProcessor = new BlockProcessor(moxane, bvts);
		resources.add(blockProcessor);
		fluidProcessor = new FluidProcessor(moxane);
		resources.add(fluidProcessor);
		veggieProcessor = new VegetationProcessor(moxane, vvts);
		resources.add(veggieProcessor);

		resources.add(new Cube);
		resources.add(new Slope);
		resources.add(new Tetrahedron);
		resources.add(new AntiTetrahedron);
		resources.add(new HorizontalSlope);
		resources.add(new FluidMesh);
		resources.add(new GrassMesh);

		resources.add(new Dirt);
		resources.add(new Grass);
		resources.add(new GrassBlade);

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
	}

	private void setCamera(Vector2i size)
	{
		camera.width = cast(uint)size.x;
		camera.height = cast(uint)size.y;
		camera.perspective.fieldOfView = 75f;
		camera.perspective.near = 0.1f;
		camera.perspective.far = 100f;
		camera.buildProjection;
		moxane.services.get!Renderer().cameraUpdated;
	}

	override void setToCurrent(Scene overwrote) 
	{}

	override void removedCurrent(Scene overwroteBy)
	{}

	private Vector2d prevCursor = Vector2d(0, 0);

	private char[1024] buffer;

	override void onUpdate() @trusted
	{
		Window win = moxane.services.get!Window;

		if(win.isFocused && win.isMouseButtonDown(MouseButton.right))
		{
			Vector2d cursor = win.cursorPos;
			Vector2d c = cursor - prevCursor;
			
			prevCursor = cast(Vector2d)win.size / 2.0;
			win.cursorPos = prevCursor;

			Vector3f rotation;
			rotation.x = cast(float)c.y * cast(float)moxane.deltaTime * 10;
			rotation.y = cast(float)c.x * cast(float)moxane.deltaTime * 10;
			rotation.z = 0f;

			camera.rotate(rotation);

			Vector3f a = Vector3f(0f, 0f, 0f);
			if(win.isKeyDown(Keys.w)) a.z += 1f;
			if(win.isKeyDown(Keys.s)) a.z -= 1f;
			if(win.isKeyDown(Keys.a)) a.x -= 1f;
			if(win.isKeyDown(Keys.d)) a.x += 1f;
			if(win.isKeyDown(Keys.q)) a.y -= 1f;
			if(win.isKeyDown(Keys.e)) a.y += 1f;

			camera.moveOnAxes(a * moxane.deltaTime);
		}

		camera.buildView;

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