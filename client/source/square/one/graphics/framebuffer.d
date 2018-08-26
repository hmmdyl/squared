module square.one.graphics.framebuffer;

/*import derelict.opengl3.gl3;
import gfm.math;

import std.conv;

import square.one.graphics.render;

class DirectionalShadowFramebuffer {
	uint width, height;

	GLuint fbo;
	GLuint depthTexture;

	RenderContext rc;

	this(RenderContext rc) {
		this.rc = rc;
		this.rc.onDepthShadowResize.add(&onResize);

		width = this.rc.depthShadowSize.x;
		height = this.rc.depthShadowSize.y;

		glEnable(GL_TEXTURE_2D);
		scope(exit) glDisable(GL_TEXTURE_2D);
	
		glGenTextures(1, &depthTexture);

		createTextures;

		glGenFramebuffers(1, &fbo);
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, depthTexture, 0);

		GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
		if(status != GL_FRAMEBUFFER_COMPLETE)
			throw new Exception("FBO " ~ to!string(fbo) ~ " could not be created. Status " ~ to!string(status));
		
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
	}

	~this() {
		glDeleteTextures(1, &depthTexture);
		glDeleteFramebuffers(1, &fbo);
	}

	void createTextures() {
		glEnable(GL_TEXTURE_2D);
		scope(exit) glDisable(GL_TEXTURE_2D);

		assert(width != 0);
		assert(height != 0);

		scope(exit) glBindTexture(GL_TEXTURE_2D, 0);

		glBindTexture(GL_TEXTURE_2D, depthTexture);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, width, height, 0, GL_DEPTH_COMPONENT, GL_FLOAT, null);
	}

	private void onResize(vec2ui s) {
		width = s.x;
		height = s.y;
		createTextures;
	}
}

class PointLightShadowFramebuffer {
	uint width, height;

	GLuint fbo;
	GLuint depthTexture;

	RenderContext rc;

	this(RenderContext rc) {
		this.rc = rc;
		this.rc.onDepthShadowResize.add(&onResize);

	}

	void createTextures() {
		glEnable(GL_TEXTURE_CUBE_MAP);
		scope(exit) glDisable(GL_TEXTURE_CUBE_MAP);


	}

	private void onResize(vec2ui s) {
		width = s.x;
		height = s.y;
		createTextures;
	}
}

class RainShadowFramebuffer {
	uint width, height;
	
	GLuint fbo;
	GLuint depthTexture;
	GLuint normalTexture;

	RenderContext rc;

	immutable GLenum[] drawBuffers = [ GL_COLOR_ATTACHMENT2 ];
	
	this(RenderContext rc) {
		this.rc = rc;
		this.rc.onDepthShadowResize.add(&onResize);
		
		width = this.rc.depthShadowSize.x;
		height = this.rc.depthShadowSize.y;
		
		glEnable(GL_TEXTURE_2D);
		scope(exit) glDisable(GL_TEXTURE_2D);
		
		glGenTextures(1, &depthTexture);
		glGenTextures(1, &normalTexture);
		
		createTextures;
		
		glGenFramebuffers(1, &fbo);
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, depthTexture, 0);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT2, GL_TEXTURE_2D, normalTexture, 0);

		glDrawBuffers(cast(int)drawBuffers.length, drawBuffers.ptr);

		GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
		if(status != GL_FRAMEBUFFER_COMPLETE)
			throw new Exception("FBO " ~ to!string(fbo) ~ " could not be created. Status " ~ to!string(status));
		
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
	}
	
	void createTextures() {
		glEnable(GL_TEXTURE_2D);
		scope(exit) glDisable(GL_TEXTURE_2D);
		
		assert(width != 0);
		assert(height != 0);
		
		scope(exit) glBindTexture(GL_TEXTURE_2D, 0);
		
		glBindTexture(GL_TEXTURE_2D, depthTexture);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, width, height, 0, GL_DEPTH_COMPONENT, GL_FLOAT, null);
	}
	
	private void onResize(vec2ui s) {
		width = s.x;
		height = s.y;
		createTextures;
	}
}*/