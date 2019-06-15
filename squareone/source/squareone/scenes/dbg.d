module squareone.scenes.dbg;

import moxane.core;
import moxane.io;
import moxane.graphics.renderer;
import moxane.graphics.firstperson;
import moxane.graphics.sprite;

import squareone.terrain.basic.manager;
import squareone.voxel;
import squareone.voxelcontent.block;

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
	private BasicTerrainRenderer terrainRenderer;
	private BasicTerrainManager terrainManager;

	private FirstPersonCamera camera;
	private SpriteFont font;

	private void initialise()
	{
		resources = new Resources;
		resources.add(new Invisible);
		resources.add(new Air);

		IBlockVoxelTexture[] bvts = new IBlockVoxelTexture[](2);
		bvts[0] = new DirtTexture;
		bvts[1] = new GrassTexture;

		blockProcessor = new BlockProcessor(moxane, bvts);
		resources.add(blockProcessor);

		resources.add(new Cube);
		resources.add(new Slope);
		resources.add(new Tetrahedron);
		resources.add(new AntiTetrahedron);
		resources.add(new HorizontalSlope);

		resources.add(new Dirt);
		resources.add(new Grass);

		resources.finaliseResources;
		BasicTMSettings settings = BasicTMSettings(Vector3i(4, 4, 4), Vector3i(8, 8, 8), Vector3i(10, 10, 10), resources);
		terrainManager = new BasicTerrainManager(moxane, settings);
		terrainRenderer = new BasicTerrainRenderer(terrainManager);

		Renderer renderer = moxane.services.get!Renderer;
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

		if(win.isFocused)
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
			if(win.isKeyDown(Keys.w)) a.z += 10f;
			if(win.isKeyDown(Keys.s)) a.z -= 10f;
			if(win.isKeyDown(Keys.a)) a.x -= 10f;
			if(win.isKeyDown(Keys.d)) a.x += 10f;
			if(win.isKeyDown(Keys.q)) a.y -= 10f;
			if(win.isKeyDown(Keys.e)) a.y += 10f;

			camera.moveOnAxes(a * moxane.deltaTime);
		}

		camera.buildView;

		terrainManager.cameraPosition = camera.position;
		terrainManager.update;

		buffer[] = char.init;
		int l = sprintf(buffer.ptr, 
"Camera position: %0.3f %0.3f %0.3f
Camera rotation: %0.3f %0.3f %0.3f
						
Delta: %0.6fs
						
Chunks: %d", 
						camera.position.x, camera.position.y, camera.position.z,
						camera.rotation.x, camera.rotation.y, camera.rotation.z,
						moxane.deltaTime,
						terrainManager.numChunks);
		moxane.services.get!SpriteRenderer().drawText(cast(string)buffer[0..l], font, Vector2i(0, 10));
	}

	override void onRenderBegin() @trusted
	{
		super.onRenderBegin;

		Window win = moxane.services.get!Window;
		import derelict.opengl3.gl3;
		if(win.isKeyDown(Keys.x))
		{
			glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
		}
		else
			glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
	}

	override void onRender()
	{}
}