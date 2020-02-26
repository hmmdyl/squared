module squareone.systems.inventory2;

import moxane.core;
public import moxane.io;
import moxane.utils.math;
import moxane.graphics;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;

import std.experimental.allocator.mallocator;
import std.algorithm : count, max;
import std.conv : to;

import derelict.opengl3.gl3;

@safe:

@Component struct ItemDefinition
{
	string technicalName;
	string displayName;

	ushort maxStack;
}

@Component struct OrthoInvenIconRender
{
	void delegate(Entity entity, InventoryRenderer ir, Renderer r,
				  uint framex, uint framey, uint iconwidth, uint iconheight,
				  ref LocalContext lc, ref uint dc, ref uint nv) invoke;
}

@Component struct PerspectiveInvenIconRender
{
	void delegate(Entity entity, InventoryRenderer ir, Renderer r,
				  uint iconWidth, uint iconHeight,
				  ref LocalContext lc, ref uint dc, ref uint nv) invoke;
}

@Component struct ItemStack { ushort size; }

@Component struct PrimaryUse { void delegate(const ref InputEvent) invoke; }
@Component struct SecondaryUse { void delegate(const ref InputEvent) invoke; }

@Component struct InventoryBase
{
	Entity[] slots;
	Vector!(ubyte, 2) dimensions;
	ubyte selectionX;

	Entity get(ubyte x, ubyte y) { return slots[flattenIndex2D(x, y, dimensions.x)]; }
	Entity getSelected() { return slots[flattenIndex2D(selectionX, dimensions.y - 1, dimensions.x)]; }
}

@Component struct ItemInventory
{	
	InventoryBase base;
	alias base this;
}

@Component struct SecondaryInventory 
{
	InventoryBase base;
	alias base this;
	bool active; 
}

@Component struct InventoryLocal { bool open; }

enum primaryUse = InventorySystem.stringof ~ ":primaryUse";
enum primaryUseDefault = MouseButton.left;
enum secondaryUse = InventorySystem.stringof ~ ":secondaryUse";
enum secondaryUseDefault = MouseButton.right;

final class InventorySystem : System
{
	private Entity target_;
	@property Entity target() { return target_; }

	this(Moxane moxane, EntityManager manager)
	{
		super(moxane, manager);

		InputManager im = moxane.services.get!InputManager;
		if(!im.hasBinding(primaryUse))
			im.setBinding(primaryUse, primaryUseDefault);
		if(!im.hasBinding(secondaryUse))
			im.setBinding(secondaryUse, secondaryUseDefault);

		im.boundKeys[primaryUse] ~= &onInput!PrimaryUse;
		im.boundKeys[secondaryUse] ~= &onInput!SecondaryUse;

		string[10] selectorBindingNames;
		Keys[10] selectorKeys;
		selectionBindings(selectorBindingNames, selectorKeys);
        foreach(x; 0 .. selectorBindingNames.length)
            im.setBinding(selectorBindingNames[x], selectorKeys[x]);
		foreach(x; 0 .. selectorBindingNames.length)
			im.boundKeys[selectorBindingNames[x]] ~= &onSelect;
	}

	~this()
	{
		InputManager im = moxane.services.get!InputManager;
		im.boundKeys[primaryUse] -= &onInput!PrimaryUse;
		im.boundKeys[secondaryUse] -= &onInput!SecondaryUse;

		string[10] selectorBindingNames;
		Keys[10] selectorKeys;
		selectionBindings(selectorBindingNames, selectorKeys);
		foreach(x; 0 .. selectorBindingNames.length)
		{
			if(!im.hasBinding(selectorBindingNames[x]))
				im.setBinding(selectorBindingNames[x], selectorKeys[x]);
			im.boundKeys[selectorBindingNames[x]] ~= &onSelect;
		}
	}

	private void selectionBindings(out string[10] bindingNames, out Keys[10] keys) pure
	{
		foreach(x; 0 .. 10) 
		{
			keys[x] = cast(Keys)(cast(int)Keys.zero + x);
			bindingNames[x] = InventorySystem.stringof ~ ":selector" ~ to!string(x);
		}
	}

	override void update()
	{
		auto candidates = entityManager.entitiesWith!(ItemInventory, InventoryLocal)();
		if(candidates.count == 0) {target_ = null; return;}
		target_ = candidates.front;

		handleCursor;
	}

	private void handleCursor()
	{

	}

	private void onInput(alias T)(ref InputEvent ie)
	{
        import std.stdio;
        writeln("onInput");

		if(target_ is null) return;

		ItemInventory* inv = target_.get!ItemInventory;
		if(inv is null) return;

		Entity item = inv.getSelected;
		if(item is null) return;

		T* component = item.get!T;
		if(component is null) return;

		component.invoke(ie);
	}

	private void onSelect(ref InputEvent ie)
	{
		auto key = ie.key - Keys.zero;
		key = key == Keys.zero ? 9 : key - 1;

		ItemInventory* inven = target_.get!ItemInventory();
		if(inven is null) return;
		inven.selectionX = cast(ubyte)key;
	}
}

final class InventoryRenderer : IRenderable
{
	Moxane moxane;
	InventorySystem system;
    Renderer renderer;
	private DepthTexture depthCanvas;
	private RenderTexture canvas;
	private Effect renderEffect;
    private uint vao, vbo;

	Camera tileCameraOrtho;

	uint canvasDrawCalls, canvasVertexCount;

	uint iconWidth, iconHeight;

	this(Moxane moxane, InventorySystem system, GLState gl, Renderer renderer) @trusted
	in(moxane !is null) in(system !is null) in(gl !is null)
	{
		this.moxane = moxane;
		this.system = system;
        this.renderer = renderer;

		auto win = moxane.services.get!Window();
		win.onFramebufferResize.add(&onFramebufferResize);
		depthCanvas = new DepthTexture(win.framebufferSize.x, win.framebufferSize.y, gl);
		canvas = new RenderTexture(win.framebufferSize.x, win.framebufferSize.y, depthCanvas, gl);
	
		renderEffect = new Effect(moxane, typeof(this).stringof);
		renderEffect.attachAndLink(
		[ 
			new Shader(AssetManager.translateToAbsoluteDir("content/shaders/inventoryRenderer.vs.glsl"), GL_VERTEX_SHADER),
			new Shader(AssetManager.translateToAbsoluteDir("content/shaders/inventoryRenderer.fs.glsl"), GL_FRAGMENT_SHADER)
		]);
		renderEffect.bind;
        renderEffect.findUniform("Position");
        renderEffect.findUniform("Size");
        renderEffect.findUniform("MVP");
        renderEffect.findUniform("Diffuse");
		renderEffect.unbind;

        glGenVertexArrays(1, &vao);
        glGenBuffers(1, &vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        auto verts = 
        [
            Vector2f(0, 0),
            Vector2f(1, 0),
            Vector2f(1, 1),
            Vector2f(1, 1),
            Vector2f(0, 1),
            Vector2f(0, 0)
        ];
        glBufferData(GL_ARRAY_BUFFER, Vector2f.sizeof * verts.length, verts.ptr, GL_STATIC_DRAW);
        glBindBuffer(GL_ARRAY_BUFFER, 0);

        renderer.passHook.addCallback(&preRenderCallback);

		tileCameraOrtho = new Camera;
		tileCameraOrtho.position = Vector3f(0, 0, 0);
		tileCameraOrtho.rotation = Vector3f(0, 0, 0);
		tileCameraOrtho.ortho.near = -1f;
		tileCameraOrtho.ortho.far = 1f;
    }

	~this() @trusted
	{
		moxane.services.get!Window().onFramebufferResize.remove(&onFramebufferResize);
		destroy(depthCanvas);
		destroy(canvas);
		destroy(renderEffect);
	}

	private void preRenderCallback(ref RendererHook hook)
	{
		if(hook.pass != RendererHookPass.beginningGlobal) return;
		if(system.target_ is null) return;
		canvasDrawCalls = 0;
		canvasVertexCount = 0;
		renderTilesToCanvas(hook);
	}

	private void renderTilesToCanvas(RendererHook hook) @trusted
	{
		canvas.bindDraw;
		canvas.clear;
		scope(exit) 
		{
			auto framebufferSize = moxane.services.get!Window().framebufferSize;
			canvas.unbindDraw(framebufferSize.x, framebufferSize.y);
		}

		ItemInventory* primaryInven = system.target_.get!ItemInventory;
		if(primaryInven is null)
		{
			moxane.services.get!Log().write(Log.Severity.warning, "Component " ~ ItemInventory.stringof ~ " absent during canvas render!");
			return;
		}
		SecondaryInventory* secondaryInven = system.target_.get!SecondaryInventory;
		uint invenWidth = primaryInven.dimensions.x + (secondaryInven !is null ? secondaryInven.dimensions.x : 0);
		uint invenHeight = max(primaryInven.dimensions.x, secondaryInven !is null ? secondaryInven.dimensions.y : 0);

		tileCameraOrtho.width = hook.renderer.uiCamera.width / invenWidth;
		tileCameraOrtho.height = hook.renderer.uiCamera.height / invenHeight;
		with(tileCameraOrtho)
		{
			ortho.left = 0f;
			ortho.right = cast(float)width;
			ortho.bottom = 0f;
			ortho.top = cast(float)height;
			isOrtho = true;
		}
		//tileCameraOrtho.deduceOrtho;
		tileCameraOrtho.buildProjection;

		LocalContext lc;
		lc.projection = tileCameraOrtho.projection;
		lc.camera = tileCameraOrtho;
		lc.type = PassType.ui;

		uint tileX;

		//glEnable(GL_SCISSOR_TEST);
		scope(exit) glDisable(GL_SCISSOR_TEST);

		void renderPrimaryInventory()
		{
			foreach(ubyte x; 0 .. primaryInven.dimensions.x)
			{
				foreach(ubyte y; 0 .. primaryInven.dimensions.y)
				{
					Entity item = primaryInven.get(x, y);
					if(item is null) continue;
					ItemDefinition* definition = item.get!ItemDefinition;
					if(definition is null) continue;
					if(definition.onRender is null) continue;

					auto graphicsX = x * tileCameraOrtho.width;
					auto graphicsY = y * tileCameraOrtho.height;

					import std.stdio;
					writeln(x, " ", y, " ", graphicsX, " ", graphicsY, " ", tileCameraOrtho.ortho);

					lc.view = translationMatrix(Vector3f(-graphicsX, graphicsY, 0));
					//glScissor(graphicsX, graphicsY, graphicsX + invenWidth, graphicsY + invenHeight);
					definition.onRender(item, hook.renderer, this, lc, canvasDrawCalls, canvasVertexCount);
				}
				tileX = x;
			}
		}

		void renderSecondaryInventory()
		{
			if(secondaryInven is null) return;

			foreach(ubyte x; 0 .. secondaryInven.dimensions.x)
			{
				foreach(ubyte y; 0 .. secondaryInven.dimensions.y)
				{
					Entity item = secondaryInven.get(x, y);
					if(item is null) continue;
					ItemDefinition* definition = item.get!ItemDefinition;
					if(definition is null) continue;
					if(definition.onRender is null) continue;

					auto graphicsX = (x + tileX) * invenWidth;
					auto graphicsY = y * invenHeight;

					lc.view = translationMatrix(Vector3f(graphicsX, graphicsY, 0));
					glScissor(graphicsX, graphicsY, graphicsX + invenWidth, graphicsY + invenHeight);
					definition.onRender(item, hook.renderer, this, lc, canvasDrawCalls, canvasVertexCount);
				}
			}
		}

		renderPrimaryInventory;
		renderSecondaryInventory;
	}

	void render(Renderer r, ref LocalContext lc, out uint dc, out uint nv) @trusted
	{
        if(lc.type != PassType.ui) return;

        glBindVertexArray(vao);
        scope(exit) glBindVertexArray(0);

        glEnableVertexAttribArray(0);
        scope(exit) glDisableVertexAttribArray(0);

        renderEffect.bind;
        scope(exit) renderEffect.unbind;

        glActiveTexture(GL_TEXTURE0);
        canvas.bindAsTexture([0, 1, 2]);
        renderEffect["Diffuse"].set(0);
		renderEffect["Position"].set(Vector2f(0, 0));
		renderEffect["Size"].set(Vector2f(1920, 1080));
		renderEffect["MVP"].set(&lc.projection);

        scope(exit) glBindBuffer(GL_ARRAY_BUFFER, 0); 
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glVertexAttribPointer(0, 2, GL_FLOAT, false, 0 , null);
        
        glDrawArrays(GL_TRIANGLES, 0, 6);
	}

	private void onFramebufferResize(Window win, Vector2i size) @trusted
	{ 
		if(win.isIconified) return;

		canvas.createTextures(size.x, size.y);
	}
}