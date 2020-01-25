module squareone.systems.inventory2;

import moxane.core;
import moxane.io;
import moxane.utils.math;
import moxane.graphics.renderer;
import moxane.graphics.gl;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;

import std.experimental.allocator.mallocator;
import std.algorithm : count;
import std.conv : to;

@safe:

@Component struct ItemDefinition
{
	string technicalName;
	string displayName;

	ushort maxStack;
	
	void delegate(Renderer renderer, InventoryRenderer ir, ref LocalContext lc, ref uint dc, ref uint nv) onRender;
}

@Component struct ItemStack { ushort size; }

@Component struct PrimaryUse { void delegate() invoke; }
@Component struct SecondaryUse { void delegate() invoke; }

@Component struct ItemInventory
{
	Entity[] slots;
	Vector!(ubyte, 2) dimensions;

	ubyte selectionX;

	Entity get(ubyte x, ubyte y) { return slots[flattenIndex2D(x, y, dimensions.x)]; }
	Entity getSelected() { return slots[flattenIndex2D(selectionX, dimensions.y - 1, dimensions.x)]; }
}

@Component struct InventoryLocal { bool open; }

@Component struct SecondaryInventory 
{ 
	Entity[] slots;
	Vector!(ubyte, 2) dimensions; 
	bool active; 
	ubyte selectionX; 
}

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
		if(target_ is null) return;

		ItemInventory* inv = target_.get!ItemInventory;
		if(inv is null) return;

		Entity item = inv.getSelected;
		if(item is null) return;

		T* component = item.get!T;
		if(component is null) return;

		component.invoke();
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
	private InventoryCanvas canvas;

	Camera tileCameraOrtho;

	uint canvasDrawCalls, canvasVertexCount;

	this(Moxane moxane, InventorySystem system) in(moxane !is null) in(system !is null)
	{
		this.moxane = moxane;
		this.system = system;

		this.moxane.services.get!Window().onFramebufferResize.add(&onFramebufferResize);
	}

	~this()
	{
		moxane.services.get!Window().onFramebufferResize.remove(&onFramebufferResize);
	}

	private void preRenderCallback(ref RendererHook hook)
	{
		if(hook.pass != RendererHookPass.beginningGlobal) return;
		if(system.target_ is null) return;
		canvasDrawCalls = 0;
		canvasVertexCount = 0;
		renderTilesToCanvas(hook);
	}

	private void renderTilesToCanvas(RendererHook hook)
	{
		canvas.bindDraw;
		canvas.clear;
		scope(exit) canvas.unbindDraw;

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
		tileCameraOrtho.deduceOrtho;
		tileCameraOrtho.buildProjection;

		LocalContext lc;
		lc.projection = tileCameraOrtho.projection;
		lc.camera = tileCameraOrtho;
		lc.type = PassType.ui;

		uint tileX, tileY;

		void renderPrimaryInventory()
		{
			foreach(x; 0 .. primaryInven.dimensions.x)
			{
				foreach(y; 0 .. primaryInven.dimensions.y)
				{
					lc.view = translationMatrix(Vector3f(x * invenWidth, y * invenHeight, 0));
					Entity item = primaryInven.get(x, y);
					if(item is null) continue;
					ItemDefinition* definition = item.get!ItemDefinition;
					if(definition is null) continue;
					if(definition.onRender is null) continue;
					definition.onRender(hook.renderer, this, lc, canvasDrawCalls, canvasVertexCount);
				}
				tileX = x;
			}
		}

		void renderSecondaryInventory()
		{
			if(secondaryInven is null) return;

			foreach(x; 0 .. secondaryInven.dimensions.x)
			{
				foreach(y; 0 .. secondaryInven.dimensions.y)
				{
					lc.view = translationMatrix(Vector3f((x + tileX) * invenWidth, y * invenHeight, 0));
					Entity item = secondaryInven.get();
				}
			}
		}
	}

	void render(Renderer r, ref LocalContext lc, out uint dc, out uint nv)
	{

	}

	private void onFramebufferResize(Window win, Vector2i size) @trusted
	{ 
		if(win.isIconified) return;

		canvas.createTextures(size.x, size.y); 
	}
}

private final class InventoryCanvas
{
	import derelict.opengl3.gl3;

	uint width, height;
	GLuint fbo;
	GLuint depth;
	GLuint diffuse;

	GLState gl;

	private static immutable GLenum[] allAttachments = [GL_COLOR_ATTACHMENT0];

	this(uint width, uint height, GLState gl) @trusted
	in(gl !is null)
	{
		this.gl = gl;
		this.width = width;
		this.height = height;

		glGenTextures(1, &diffuse);
		glGenTextures(1, &depth);
		createTextures(width, height);

		glGenFramebuffers(1, &fbo);
		alias glfbo = GL_FRAMEBUFFER;
		alias glColAtt0 = GL_COLOR_ATTACHMENT0;

		glBindFramebuffer(glfbo, fbo);
		scope(exit) glBindFramebuffer(glfbo, 0);

		glFramebufferTexture2D(glfbo, glColAtt0, GL_TEXTURE_2D, diffuse, 0);
		glFramebufferTexture2D(glfbo, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, depth, 0);
		glDrawBuffers(cast(int)allAttachments.length, allAttachments.ptr);
		GLenum status = glCheckFramebufferStatus(glfbo);
		import std.exception;
		enforce(status == GL_FRAMEBUFFER_COMPLETE, "FBO " ~ to!string(fbo) ~ " could not be created. Status: " ~ to!string(status));
	}

	void createTextures(uint w, uint h) @trusted
	in(w > 0) in(h > 0)
	{
		this.width = w;
		this.height = h;

		/// aliases because I am a lazy cunt
		alias tex2D = GL_TEXTURE_2D;
		alias minF = GL_TEXTURE_MIN_FILTER;
		alias maxF = GL_TEXTURE_MAG_FILTER;

		scope(exit) glBindTexture(tex2D, 0);

		glBindTexture(tex2D, diffuse);
		glTexParameteri(tex2D, minF, GL_NEAREST);
		glTexParameteri(tex2D, maxF, GL_NEAREST);
		glTexImage2D(tex2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_INT, null);

		glBindTexture(tex2D, depth);
		glTexParameteri(tex2D, minF, GL_NEAREST);
		glTexParameteri(tex2D, maxF, GL_NEAREST);
		glTexImage2D(tex2D, 0, GL_DEPTH_COMPONENT, w, h, 0, GL_DEPTH_COMPONENT, GL_FLOAT, null);
	}

	~this() @trusted
	{
		glDeleteTextures(1, &diffuse);
		glDeleteTextures(1, &depth);
		glDeleteFramebuffers(1, &fbo);
	}

	debug private bool isBound;

	void bindDraw() @trusted
	{
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		glViewport(0, 0, width, height);

		debug isBound = true;
	}

	void unbindDraw(uint w, uint h) @trusted
	{
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
		glViewport(0, 0, w, h);

		debug isBound = false;
	}

	void clear() @trusted
	{
		debug { assert(isBound, "FBO must be bound to clear."); }

		glClearColor(0f, 0f, 0f, 0f);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	}

	void bindAsTexture(uint[2] textureUnits) @trusted
	{
		glActiveTexture(GL_TEXTURE0 + textureUnits[0]);
		glBindTexture(GL_TEXTURE_2D, depth);
		glActiveTexture(GL_TEXTURE0 + textureUnits[1]);
		glBindTexture(GL_TEXTURE_2D, diffuse);
	}

	void unbindTextures(uint[2] textureUnits) @trusted
	{
		foreach(uint tu; textureUnits)
		{
			glActiveTexture(GL_TEXTURE0 + tu);
			glBindTexture(GL_TEXTURE_2D, 0);
		}
	}
}