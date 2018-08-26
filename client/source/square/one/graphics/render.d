module square.one.graphics.render;

/*import moxana.graphics.effect;
import moxana.graphics.framebuffer;
import moxana.graphics.light;
import moxana.graphics.postproc;
import moxana.graphics.view;
import moxana.utils.loadable;
import moxana.io.window;
import moxana.graphics.perspective;
import moxana.graphics.text;
import moxana.utils.event;

import square.one.graphics.framebuffer;

import gfm.math;

import containers.dynamicarray;
import containers.unrolledlist;

import derelict.opengl3.gl3;

import accessors;

struct FramebufferLightPool(T, int max) {
	int count;
	int countPreviousFrame;

	T[max] buffer;
}

class RenderContext : ILoadable {
	Window window;

	PerspectiveData perspective;
	mat4f orthogonal;

	View view;

	Framebuffer physicalFramebuffer;
	Framebuffer postPhysicalFramebuffer;
	PostProcessFramebuffer[2] alternatingFramebuffers;

	FramebufferLightPool!(DirectionalShadowFramebuffer, 4) directionalFramebufferLightPool;


	float pointLightShadowDist = 0f;
	DynamicArray!PointLight pointLights;
	DynamicArray!DirectionalLight directionalLights;

	UnrolledList!IRenderHandler rainShadowRenderables;
	UnrolledList!IRenderHandler shadowRenderables;
	UnrolledList!IRenderHandler physicalRenderables;
	UnrolledList!IRenderHandler postPhysicalRenderables;
	UnrolledList!IRenderHandler uiRenderables;

	DynamicArray!(PostProcess!PostProcessFramebuffer) postProcesses; 
	PointLightPostProcess pointLightPP;
	DirectionalLightPostProcess directionalLightPP;

	enum uint depthShadowSizeDefault = 1024;

	private vec2ui depthShadowSize_;
	@property const(vec2ui) depthShadowSize() { return depthShadowSize_; }
	@property void depthShadowSize(vec2ui s) {
		depthShadowSize_ = s;
		onDepthShadowResize.emit(s);
	}
	Event!vec2ui onDepthShadowResize;

	TextRenderer textRenderer;

	GLenum polygonMode;

	this(Window window, bool allowCallbackBinds = true) {
		this.window = window;

		if(allowCallbackBinds)
			bindCallbacks;

		buildProjectionMatrices(window.framebufferSize);
	}

	void load() {
		physicalFramebuffer = new Framebuffer(window.framebufferSize.x, window.framebufferSize.y);
		postPhysicalFramebuffer = new Framebuffer(window.framebufferSize.x, window.framebufferSize.y);
		alternatingFramebuffers[0] = new PostProcessFramebuffer(window.framebufferSize.x, window.framebufferSize.y);
		alternatingFramebuffers[1] = new PostProcessFramebuffer(window.framebufferSize.x, window.framebufferSize.y);
		pointLightPP = new PointLightPostProcess;
		directionalLightPP = new DirectionalLightPostProcess;
		
		textRenderer = new TextRenderer();
	}

	private void onFBResize(Window win, vec2i newWinSize) {
		buildProjectionMatrices(newWinSize);

		physicalFramebuffer.width = newWinSize.x;
		physicalFramebuffer.height = newWinSize.y;
		physicalFramebuffer.createTextures;
		
		postPhysicalFramebuffer.width = newWinSize.x;
		postPhysicalFramebuffer.height = newWinSize.y;
		postPhysicalFramebuffer.createTextures;
		
		alternatingFramebuffers[0].width = newWinSize.x;
		alternatingFramebuffers[0].height = newWinSize.y;
		alternatingFramebuffers[0].createTextures;
		
		alternatingFramebuffers[1].width = newWinSize.x;
		alternatingFramebuffers[1].height = newWinSize.y;
		alternatingFramebuffers[1].createTextures;
	}

	void bindCallbacks() {
		window.onFramebufferResize.add(&onFBResize);
	}

	void buildProjectionMatrices(vec2i size) {
		orthogonal = mat4f.orthographic(0, size.x, size.y, 0, -1, 1);
		perspective.ratio = cast(float)size.x / cast(float)size.y;
		perspective.build;
	}

	void update() {
		textRenderer.orthogonal = orthogonal;
	}
}

class Distributor {
	RenderContext rc;

	this(RenderContext rc) {
		this.rc = rc;
	}

	void RenderAll() {

	}

	private void rainShadow() {

	}
}

interface IRenderHandler {
	void RenderRainShadowPass(RenderContext rc);
	void RenderShadowPass(RenderContext rc);
	void RenderPhysicalPass(RenderContext rc);
	void RenderPostPhysicalPass(RenderContext rc);
	void RenderUIPass(RenderContext rc);
}*/