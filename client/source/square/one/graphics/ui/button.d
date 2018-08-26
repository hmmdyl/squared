module square.one.graphics.ui.button;

import moxana.graphics.rendercontext;
import moxana.graphics.text;
import moxana.graphics.effect;
import moxana.utils.event;

import square.one.engine;

import containers.unrolledlist;

import std.file;
import std.path;
import std.meta;

import derelict.opengl3.gl3;
import gfm.math;

enum ButtonState {
	inactive,
	hover,
	click
}

class ColourButton {
	static ColourButtonRenderer renderer;
	
	vec4f inactiveColour;
	vec4f hoverColour;
	vec4f clickColour;
	
	vec2f position;
	vec2f size;
	
	string text;
	Font font;
	vec2f textPos;
	vec3f textColour;
	
	ButtonState previous, current;
	
	static Event!ColourButton onStatus;
	
	this() {
		if(renderer is null)
			renderer = new ColourButtonRenderer();
	}

	void update(vec2f mouseCoord, bool isClickDown) {
		float maxX = position.x + size.x;
		float maxY = position.y + size.y;

		ButtonState bs;

		if(mouseCoord.x >= position.x && mouseCoord.x <= maxX && mouseCoord.y >= position.y && mouseCoord.y <= maxY) {
			if(isClickDown) bs = ButtonState.click;
			else bs = ButtonState.hover;
		}
		else bs = ButtonState.inactive;
		
		if(bs != previous) {
			previous = current;
			current = bs;
			onStatus.emit(this);
		}
	}

	void render() {
		renderer.render(this);
	}
}

class ColourButtonRenderer {
	private uint vao, vbo;
	private Effect effect;
	
	RenderContext rc;
	
	this() {
		rc = engine.renderContext;
		
		ShaderEntry[] shaders = new ShaderEntry[](2);

		string vertS = readText(buildPath(getcwd(), "assets/shaders/button_colour.vs.glsl"));
		string fragS = readText(buildPath(getcwd(), "assets/shaders/button_colour.fs.glsl"));
		shaders[0] = ShaderEntry(vertS, GL_VERTEX_SHADER);
		shaders[1] = ShaderEntry(fragS, GL_FRAGMENT_SHADER);
		effect = new Effect(shaders);
		effect.bind;
		effect.findUniform("Colour");
		effect.findUniform("ModelViewProjection");
		effect.findUniform("Position");
		effect.findUniform("Size");
		effect.unbind;
		
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
	
	void render(ColourButton button) {
		//setRenderBoxState();
		//renderBox(button);
		//unsetRenderBoxState();
		renderFonts(button);
	}
	
	private alias ColourButtonSeq = AliasSeq!(ColourButton);
	
	void renderMultiple(ColourButton...)(ColourButton args) {
		glEnable(GL_BLEND);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
		scope(exit) glDisable(GL_BLEND);
		
		setRenderBoxState();
		foreach(ColourButton b; args) renderBox(b);
		unsetRenderBoxState();

		foreach(ColourButton b; args) renderFonts(b);
	}
	
	private void setRenderBoxState() {
		effect.bind();
		glBindVertexArray(vao);
		glEnableVertexAttribArray(0);
		
		mat4f proj = rc.orthogonal;
		effect["ModelViewProjection"].set(&proj, true);
		
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glVertexAttribPointer(0, 2, GL_FLOAT, false, 0, null);
		scope(exit) glBindBuffer(GL_ARRAY_BUFFER, 0);
	}
	
	private void unsetRenderBoxState() {
		glDisableVertexAttribArray(0);
		glBindVertexArray(0);
		effect.unbind();
	}
	
	private void renderBox(ColourButton b) {		
		ButtonState bs = b.current;

		if(bs == ButtonState.click) effect["Colour"].set(b.clickColour);
		else if(bs == ButtonState.hover) effect["Colour"].set(b.hoverColour);
		else effect["Colour"].set(b.inactiveColour);
		
		effect["Position"].set(b.position);
		effect["Size"].set(b.size);
		
		glDrawArrays(GL_TRIANGLES, 0, 6);
	}
	
	private void renderFonts(ColourButton b) {
		rc.textRenderer.render(b.font, b.text, b.textPos, b.textColour);
	}
}

struct TextureButton {
	
}