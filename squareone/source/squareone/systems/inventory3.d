module squareone.systems.inventory3;

import moxane.core;
import moxane.graphics;
import moxane.io;
import moxane.utils.math : flattenIndex2D;

import derelict.opengl3.gl3;
import dlib.math;

import std.exception : enforce;

@safe:

class Inventory
{
	string name;
	string technical;

	ubyte width, height;
	ubyte iconWidth, iconHeight;
	Vector2i spacing;
	
	Entity[] slots;
	Entity slot(uint x, uint y) { return slots[flattenIndex2D(x, y, width)]; }
	void slot(Entity e, uint x, uint y) { slots[flattenIndex2D(x, y, width)] = e; }

	Canvas canvas;
	Renderer renderer;
	Camera camera;

	Vector2i position;
	bool active;

	this(ubyte width, ubyte height, ubyte iconWidth, ubyte iconHeight,
		 Renderer renderer, string name)
	in(renderer !is null) in(name !is null)
	{
		enforce(width > 0);
		enforce(height > 0);
		enforce(iconWidth > 0);
		enforce(iconHeight > 0);

		this.width = width;
		this.height = height;
		this.iconWidth = iconWidth;
		this.iconHeight = iconHeight;
		this.renderer = renderer;
		scope(success) renderer.passHook.addCallback(&preRender);
		this.name = name;
		this.technical = name;
		spacing = Vector2i(0, 0);

		slots = new Entity[](width * height);
		canvas = new Canvas(width * iconWidth, height * iconHeight);
		camera = new Camera;
		camera.position = Vector3f(0, 0, 0);
		camera.rotation = Vector3f(0, 0, 0);
		camera.ortho.near = -1f;
		camera.ortho.far = 1f;
		camera.width = width * iconWidth;
		camera.height = height * iconHeight;
		camera.deduceOrtho;
		camera.buildProjection;
		camera.buildView;
	}

	~this()
	{
		renderer.passHook.removeCallback(&preRender);
	}

	void dimensionsUpdated()
	{
		canvas.createTextures(width * iconWidth, height * iconHeight);
		camera.width = width * iconWidth;
		camera.height = height * iconHeight;
		camera.deduceOrtho;
		camera.buildProjection;
		camera.buildView;
	}

	private void preRender(ref RendererHook hook)
	{
		if(hook.pass != RendererHookPass.beginningGlobal) return;
		renderCanvas;
	}

	private void renderCanvas()
	{
		canvas.draw;
		canvas.clear;
		scope(exit) canvas.endDraw;

		LocalContext lc;
		lc.camera = camera;
		lc.model = Matrix4f.identity;
		lc.projection = camera.projection;
		lc.view = camera.viewMatrix;
		lc.type = PassType.ui;

		foreach(x; 0 .. width)
		foreach(y; 0 .. height)
		{
			Entity e = slot(x, y);
			ItemRender* itemRender = e.get!ItemRender;
			if(itemRender is null) continue;

			itemRender.invoke(this, e, lc, x, y, iconWidth, iconHeight);
		}
	}
} 

class InventoryInput : System
{
	Inventory[] inventories;

	this(Moxane moxane, EntityManager em) { super(moxane, em); }

	override void update()
	{

	}
}

@Component struct InventoryComponent
{
	Inventory inventory;
}

@Component struct ItemDefinition
{
	string technicalName;
	string displayName;

	ushort maxStack;
}

@Component struct ItemRender
{
	void delegate(Inventory inventory, Entity e, ref LocalContext lc,
				  uint x, uint y, uint w, uint h) invoke;
}

@Component struct ItemStack { ushort size; }

@Component struct ItemPrimaryUse { void delegate(const ref InputEvent) invoke; }
@Component struct ItemSecondaryUse { void delegate(const ref InputEvent) invoke; }

bool isValidInventoryItem(Entity e)
{ return e.has!ItemDefinition() && e.has!ItemStack(); }

class Canvas
{
	uint width, height;
	invariant {
		assert(width > 0);
		assert(height > 0);
	}

	uint fbo, diffuse, depth;

	this(uint width, uint height) @trusted
	{
		glGenTextures(1, &diffuse);
		glGenTextures(1, &depth);
		createTextures(width, height);

		glGenFramebuffers(1, &fbo);
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, diffuse, 0);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, depth, 0);
		glDrawBuffer(GL_COLOR_ATTACHMENT0);

		auto status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
		assert(status == GL_FRAMEBUFFER_COMPLETE);

		glBindFramebuffer(GL_FRAMEBUFFER, 0);
	}

	~this() @trusted
	{
		glDeleteTextures(1, &diffuse);
		glDeleteTextures(1, &depth);
		glDeleteFramebuffers(1, &fbo);
	}

	void createTextures(uint width, uint height) @trusted
	{
		scope(exit) glBindTexture(GL_TEXTURE_2D, 0);

		glBindTexture(GL_TEXTURE_2D, diffuse);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);

		glBindTexture(GL_TEXTURE_2D, depth);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, width, height, 0, GL_DEPTH_COMPONENT, GL_FLOAT, null);
	}

	void clear() @trusted
	{ 
		glClearColor(0f, 0f, 0f, 0f);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	}

	void draw() @trusted 
	{
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		glViewport(0, 0, width, height);
	}

	void endDraw() @trusted
	{
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
		glViewport(0, 0, width, height);
	}
}