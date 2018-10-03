module square.one.graphics.ui.picture;

import moxana.graphics.rendercontext;
import moxana.graphics.effect;

import moxana.graphics.bitmap;
import moxana.graphics.texture2d;

import square.one.engine;

import std.file;
import std.path;

import derelict.opengl3.gl3;
import gfm.math;

class Picture {
	vec2f position;
	vec2f size;

	private Texture2D texture_;
	@property Texture2D texture() { return texture_; }

	this() {

	}

	~this() {
		if(texture_ !is null)
			destroy(texture_);
	}

	void setPicture(string file, GLenum min = GL_LINEAR, GLenum mag = GL_LINEAR) {
		if(texture_ !is null) {
			destroy(texture);
		}

		texture_ = new Texture2D(file, min, mag, true);
	}
}

class PictureRenderer {
	private uint vbo, vao;
	private Effect effect;

	RenderContext rcore;

	this() {
		rcore = engine.renderContext;
		if(rcore is null)
			throw new Exception("Service RendererCore must not be null!");

		ShaderEntry[] shaders = new ShaderEntry[](2);
		shaders[0] = ShaderEntry(readText(buildPath(getcwd(), "assets/shaders/picture_box.vs.glsl")), GL_VERTEX_SHADER);
		shaders[1] = ShaderEntry(readText(buildPath(getcwd(), "assets/shaders/picture_box.fs.glsl")), GL_FRAGMENT_SHADER);
		effect = new Effect(shaders, PictureRenderer.stringof);
		effect.bind();
		effect.findUniform("Position");
		effect.findUniform("Size");
		effect.findUniform("Projection");
		effect.findUniform("Texture");
		effect.unbind();

		glGenVertexArrays(1, &vao);
		glGenBuffers(1, &vbo);

		vec2f[] verts = [
			vec2f(0, 0),
			vec2f(1, 0),
			vec2f(1, 1),
			vec2f(1, 1),
			vec2f(0, 1),
			vec2f(0, 0)
		];
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, vec2f.sizeof * verts.length, verts.ptr, GL_STATIC_DRAW);
		glBindBuffer(GL_ARRAY_BUFFER, 0);
	}

	~this() {
		destroy(effect);
		glDeleteBuffers(1, &vbo);
		glDeleteVertexArrays(1, &vao);
	}

	void render(Picture pic) {
		glEnable(GL_BLEND);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
		scope(exit) glDisable(GL_BLEND);

		effect.bind();
		scope(exit) effect.unbind();

		glBindVertexArray(vao);
		scope(exit) glBindVertexArray(0);

		glEnableVertexAttribArray(0);
		scope(exit) glDisableVertexAttribArray(0);

		mat4f proj = rcore.orthogonal;
		effect["Projection"].set(&proj, true);

		effect["Position"].set(pic.position);
		effect["Size"].set(pic.size);

		Texture2D.enable();
		glActiveTexture(GL_TEXTURE0);
		scope(exit) Texture2D.disable();
		effect["Texture"].set(0);

		glBindTexture(GL_TEXTURE_2D, pic.texture.id);

		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glVertexAttribPointer(0, 2, GL_FLOAT, false, 0, null);
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		glDrawArrays(GL_TRIANGLES, 0, 6);
	}
}