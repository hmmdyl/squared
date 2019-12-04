module squareone.systems.inventory;

import moxane.core;
import moxane.network.semantic;
import moxane.graphics.renderer;
import moxane.graphics.texture;
import moxane.graphics.gl;
import moxane.graphics.sprite;

import derelict.opengl3.gl3;
import std.exception : enforce;
import std.conv : to;
import dlib.math.vector : Vector2i, Vector3f;
import std.algorithm;
import std.range;

/// Represents a distinct family of IItemTypes. This can be used for common data between all types.
@safe interface IItemFamily
{
	/// An item belonging to this family was selected.
	void onSelect(IItemType type, ref ItemStack stack);
	/// An item belonging to this family was deselected.
	void onDeselect(IItemType type, ref ItemStack stack);
}

/// Represents a type of item.
@safe interface IItemType
{
	/// Encompassing family
	@property TypeInfo family();

	/// Render tile
	void renderTile(PlayerInventorySystem pis, Renderer renderer, ref LocalContext lc, ref uint dc, ref uint nv);

	void onSelect(IItemType type, ref ItemStack stack);
	void onDeselect(IItemType type, ref ItemStack stack);

	@property ushort maxPerSlot() const;
}

@safe struct ItemInstance
{
	IItemType type;
	void* data;
}

@safe struct ItemStack
{
	ItemInstance representative;
	ushort count;
}

@safe struct PlayerInventory
{
	ClientID client;

	int width, height;
	bool hotbar;

	bool[][] slotUsed;
	ItemStack[][] slots;
}

@safe struct PlayerInventoryLocal
{
	bool isOpen;
	int hotbarSel;
	int meshSel;
}

@safe class PlayerInventoryRenderer : IRenderable
{
	private PlayerInventorySystem system_;
	@property PlayerInventorySystem system() { return system_; }

	private PiRenderTexture canvas;

	this(PlayerInventorySystem system) in(system !is null)
	{
		this.system_ = system;	
	}

	private void renderHookCallback(ref RendererHook hook) @trusted
	{
		if(hook.pass != RendererHookPass.beginningGlobal) return;
		if(system_.target is null) return;

		if(system_.renderer.uiCamera.height != canvas.height || system_.renderer.uiCamera.width != canvas.width)
			canvas.createTextures(system_.renderer.uiCamera.width, system_.renderer.uiCamera.height);
	}

	void render(Renderer r, ref LocalContext lc, out uint dc, out uint nv) @trusted
	{
		if(system_.target is null) return;

		PlayerInventory* pi = system.target.get!PlayerInventory;
		if(pi is null) return;
		PlayerInventoryLocal* pil = system.target.get!PlayerInventoryLocal;
		if(pil is null) return;

		SpriteRenderer sprite = system_.moxane.services.get!SpriteRenderer;
		uint w = lc.camera.width;
		uint h = lc.camera.height;

		if(pil.isOpen)
		{
			// render inventory
			{
				// background
				int startX = lc.camera.width / 5;
				int startY = lc.camera.height / 5;
				int endX = lc.camera.width / 5 * 3;
				int endY = lc.camera.height / 10 * 7;
				sprite.drawSprite(Vector2i(startX, startY), Vector2i(endX, endY), Vector3f(0.5f, 0.5f, 0.5f), 0.4f);
			}
		}

		// render hotbar
		{
			// background
			int startX = lc.camera.width / 5;
			int startY = lc.camera.height - (lc.camera.height / 14);
			int endX = lc.camera.width / 5 * 3;
			int endY = lc.camera.height / 15;
			sprite.drawSprite(Vector2i(startX, startY), Vector2i(endX, endY), Vector3f(0.5f, 0.5f, 0.5f), 0.4f);
		}
	}
}

@safe class PlayerInventorySystem : System
{
	Renderer renderer;

	private Entity target_;
	@property Entity target() { return target_; }

	PlayerInventoryRenderer inventoryRenderer;

	this(Moxane moxane, Renderer renderer, EntityManager manager, bool addRenderer = true)
	in(moxane !is null) in(manager !is null)
	{
		super(moxane, manager);
		this.renderer = renderer;

		if(renderer !is null)
		{
			inventoryRenderer = new PlayerInventoryRenderer(this);
			if(addRenderer)
				renderer.uiRenderables ~= inventoryRenderer;
		}

		seekTarget;
	}

	~this() @trusted
	{
		if(canFind(renderer.uiRenderables, inventoryRenderer))
			remove!(a => a == inventoryRenderer)(renderer.uiRenderables);
		destroy(inventoryRenderer);
		inventoryRenderer = null;
	}

	void seekTarget()
	{
		// NOTE: optimise this? Don't need to check *every* frame 
		auto candidates = entityManager.entitiesWith!(PlayerInventory, PlayerInventoryLocal)
			.filter!(a => a.get!PlayerInventory().client == entityManager.clientID);
		target_ = candidates.empty ? null : candidates.front;
	}

	override void update()
	{
		seekTarget;
	}
}

private final class PiRenderTexture
{
	uint width, height;
	GLuint fbo;
	GLuint depth;
	GLuint diffuse;

	GLState gl;

	private static immutable GLenum[] allAttachments = [GL_COLOR_ATTACHMENT0];

	this(uint width, uint height, GLState gl)
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
		enforce(status == GL_FRAMEBUFFER_COMPLETE, "FBO " ~ to!string(fbo) ~ " could not be created. Status: " ~ to!string(status));
	}

	void createTextures(uint w, uint h)
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

	~this()
	{
		glDeleteTextures(1, &diffuse);
		glDeleteTextures(1, &depth);
		glDeleteFramebuffers(1, &fbo);
	}

	debug private bool isBound;

	void bindDraw()
	{
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		glViewport(0, 0, width, height);

		debug isBound = true;
	}

	void unbindDraw(uint w, uint h)
	{
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
		glViewport(0, 0, w, h);

		debug isBound = false;
	}

	void clear()
	{
		debug { assert(isBound, "FBO must be bound to clear."); }

		glClearColor(0f, 0f, 0f, 0f);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	}

	void bindAsTexture(uint[2] textureUnits)
	{
		glActiveTexture(GL_TEXTURE0 + textureUnits[0]);
		glBindTexture(GL_TEXTURE_2D, depth);
		glActiveTexture(GL_TEXTURE0 + textureUnits[1]);
		glBindTexture(GL_TEXTURE_2D, diffuse);
	}

	void unbindTextures(uint[2] textureUnits)
	{
		foreach(uint tu; textureUnits)
		{
			glActiveTexture(GL_TEXTURE0 + tu);
			glBindTexture(GL_TEXTURE_2D, 0);
		}
	}
}