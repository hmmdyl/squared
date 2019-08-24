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

interface IItemType
{
	void renderTile(PlayerInventorySystem pis, Renderer renderer, ref LocalContext lc, ref uint dc, ref uint nv);
}

struct ItemInstance
{
	IItemType type;
	void* data;
}

struct ItemStack
{
	ItemInstance representative;
	ushort count;
}

struct PlayerInventory
{
	int width, height;
	bool hotbar;

	bool[][] slotUsed;
	ItemStack[][] slots;
}

struct PlayerInventoryLocal
{
	bool isOpen;
	int hotbarSel;
	int meshSel;
}

class PlayerInventorySystem : IRenderable
{
	Moxane moxane;
	Renderer renderer;

	private IItemType[] itemTypes_;
	@property IItemType[] itemTypes() { return itemTypes; }
	private Texture2D[] renderedItems;

	private PiRenderTexture canvas;

	Vector2i slotRenderSize;

	this(Moxane moxane, Renderer renderer, IItemType[] itemTypesIn)
	{
		assert(moxane !is null && renderer !is null);
		this.moxane = moxane;
		this.renderer = renderer;
		this.itemTypes_ = itemTypesIn;

		enforce(renderer.uiCamera !is null);
		canvas = new PiRenderTexture(renderer.uiCamera.width, renderer.uiCamera.height, renderer.gl);

		//this.renderer.passHook.addCallback(&renderHookCallback);
	}

	Entity target;

	private void renderHookCallback(ref RendererHook hook) @trusted
	{
		if(hook.pass != RendererHookPass.beginningGlobal) return;
		if(target is null) return;

		if(renderer.uiCamera.height != canvas.height || renderer.uiCamera.width != canvas.width)
			canvas.createTextures(renderer.uiCamera.width, renderer.uiCamera.height);
		
	}

	void render(Renderer r, ref LocalContext lc, out uint dc, out uint nv)
	{
		if(target is null) return;

		PlayerInventory* pi = target.get!PlayerInventory;
		if(pi is null) return;
		PlayerInventoryLocal* pil = target.get!PlayerInventoryLocal;
		if(pil is null) return;

		SpriteRenderer sprite = moxane.services.get!SpriteRenderer;
		uint w = lc.camera.width;
		uint h = lc.camera.height;

		if(pil.isOpen)
		{
			// render inventory
			{
				// background
				int startX = lc.camera.width / 5;
				int startY = lc.camera.height / 5;
				int endX = lc.camera.width / 5;
				int endY = lc.camera.height / 5;
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