module square.one.misc.sky;

import moxana.graphics.effect;
import moxana.graphics.rendercontext;
import moxana.graphics.rh;
import moxana.graphics.view;
import moxana.graphics.rgbconv;
import moxana.graphics.lighting;

import square.one.graphics.modelloader;
import square.one.ingametime.ingametime;

import std.file;
import std.path;
import std.math;
import std.typecons;

import derelict.opengl3.gl3;
import gfm.math;

class Sky : IRenderHandler {
	immutable Tuple!(IngameTime, IngameTime, vec3f)[] coloursPerTime = [
		tuple(IngameTime(5, 35), IngameTime(5, 40), rgbToVec(0, 0, 0)),
		tuple(IngameTime(5, 40), IngameTime(6, 2), rgbToVec(255, 63, 28)),		/* START SUNRISE */
		tuple(IngameTime(6, 2), IngameTime(6, 3), rgbToVec(255, 80, 28)),
		tuple(IngameTime(6, 3), IngameTime(6, 4), rgbToVec(255, 100, 28)),
		tuple(IngameTime(6, 4), IngameTime(6, 5), rgbToVec(255, 115, 28)),
		tuple(IngameTime(6, 5), IngameTime(6, 10), rgbToVec(255, 128, 28)),
		tuple(IngameTime(6, 10), IngameTime(6, 11), rgbToVec(255, 175, 111)),
		tuple(IngameTime(6, 11), IngameTime(6, 12), rgbToVec(255, 196, 147)),
		tuple(IngameTime(6, 12), IngameTime(6, 13), rgbToVec(255, 207, 168)),
		tuple(IngameTime(6, 13), IngameTime(6, 14), rgbToVec(255, 227, 204)),	/* END SUNRISE */
		tuple(IngameTime(6, 14), IngameTime(17, 46), rgbToVec(255, 255, 255)),	/* MID DAY */
		tuple(IngameTime(17, 46), IngameTime(17, 47), rgbToVec(255, 227, 204)),	/* START EVENING */
		tuple(IngameTime(17, 47), IngameTime(17, 48), rgbToVec(255, 207, 168)),
		tuple(IngameTime(17, 48), IngameTime(17, 49), rgbToVec(255, 196, 147)),
		tuple(IngameTime(17, 49), IngameTime(17, 50), rgbToVec(255, 175, 111)),
		tuple(IngameTime(17, 50), IngameTime(17, 55), rgbToVec(255, 128, 28)),
		tuple(IngameTime(17, 55), IngameTime(17, 56), rgbToVec(255, 115, 28)),
		tuple(IngameTime(17, 56), IngameTime(17, 57), rgbToVec(255, 100, 28)),
		tuple(IngameTime(17, 57), IngameTime(17, 58), rgbToVec(255, 80, 28)),
		tuple(IngameTime(17, 58), IngameTime(18, 20), rgbToVec(255, 63, 28)),
	];

	IngameTime time;
	View view;

	vec3f playerPosition;

	private DirectionalLight light;
	@property DirectionalLight sunLight() { return light; }

	private AtmosphereRenderer atmosphere;
	@property AtmosphereRenderer atmosphereRenderer() { return atmosphere; }

	this(View view) {
		this.view = view;

		//light = new DirectionalLight;
		light.ambientIntensity = 0.05f;
		light.diffuseIntensity = 1f;

		atmosphere = new AtmosphereRenderer();
	}

	void update(IngameTime time) {
		this.time = time;

		light.direction = time.timeToSun;
		//light.shadowOrigin = light.direction * 50f;// + playerPosition;
		atmosphere.sunDirection = time.timeToSun;

		bool set = false;
		foreach(int i, Tuple!(IngameTime, IngameTime, vec3f) colour; coloursPerTime) {
			if(time >= colour[0] && time <= colour[1]) {
				Tuple!(IngameTime, IngameTime, vec3f) next = void;
				bool slerp = false;

				if(i < coloursPerTime.length - 1) {
					next = coloursPerTime[i + 1];
					slerp = true;
				}

				if(slerp) {
					IngameTime startOfThis = colour[0];
					IngameTime startOfNext = next[0];

					float base = startOfThis.asDecimal / 24f;
					float nextDec = startOfNext.asDecimal / 24f;
					float timeDec = time.asDecimal / 24f;

					float w = (timeDec - base) / (-base + nextDec);

					//float weight = lerp(base, nextDec, timeDec);
					light.colour = lerp(colour[2], next[2], w);

					//std.stdio.writeln(w, " ", light.colour);
				}
				else {
					light.colour = colour[2];
				}
				set = true;
			}
		}
		if(!set) light.colour = vec3f(0f, 0f, 0f);
	}

	void shadowDepthMapPass(RenderContext rc, ref LocalRenderContext lrc) {}
	void renderPhysical(RenderContext rc, ref LocalRenderContext lrc) {}
	void ui(RenderContext rc) {}

	void renderPostPhysical(RenderContext rc, ref LocalRenderContext lrc) {
		atmosphere.render(rc, vec3f(0f, 0f, 0f));
	}
}

class AtmosphereRenderer {
	private Effect effect;
	private uint vbo, nbo, vao;
	
	private int vertexCount;
	
	vec3f sunDirection;
	float scale;

	enum float earthRadius = 6371000;

	this(float scale = 637.1f) {
		this.scale = scale;
		sunDirection = vec3f(0f, 0f, 0f);
		
		ShaderEntry[] shaders = [
			ShaderEntry(readText(buildPath(getcwd(), "assets/shaders/atmospheric_scattering.vs.glsl")), GL_VERTEX_SHADER),
			ShaderEntry(readText(buildPath(getcwd(), "assets/shaders/atmospheric_scattering.fs.glsl")), GL_FRAGMENT_SHADER)
		];
		effect = new Effect(shaders, AtmosphereRenderer.stringof);
		effect.bind();
		effect.findUniform("ModelViewProjection");
		effect.findUniform("Model");
		effect.findUniform("CamPos");
		effect.findUniform("SunDirection");
		effect.unbind();
		
		vec3f[] verts, norms;
		loadModelVertsNorms(buildPath(getcwd(), "assets/models/sphere.dae"), verts, norms);
		vertexCount = cast(int)verts.length;
		
		glGenVertexArrays(1, &vao);
		glGenBuffers(1, &vbo);
		glGenBuffers(1, &nbo);
		
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, vec3f.sizeof * verts.length, verts.ptr, GL_STATIC_DRAW);
		
		glBindBuffer(GL_ARRAY_BUFFER, nbo);
		glBufferData(GL_ARRAY_BUFFER, vec3f.sizeof * norms.length, norms.ptr, GL_STATIC_DRAW);
		
		glBindBuffer(GL_ARRAY_BUFFER, 0);
	}

	void render(RenderContext rc, vec3f cameraPos) {
		mat4f translation = mat4f.translation(cameraPos) * mat4f.scaling(vec3f(scale, scale, scale));		
		mat4f mvp = rc.primaryProj.matrix * rc.view.matrix * translation;
		
		effect.bind();
		
		effect["ModelViewProjection"].set(&mvp, true);
		effect["Model"].set(&translation, true);
		effect["CamPos"].set(vec3f(0, 6372000, 0));
		effect["SunDirection"].set(sunDirection);
		
		glBindVertexArray(vao);
		
		glEnableVertexAttribArray(0);	
		glEnableVertexAttribArray(1);
		
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, null);
		
		glBindBuffer(GL_ARRAY_BUFFER, nbo);
		glVertexAttribPointer(1, 3, GL_FLOAT, false, 0, null);
		
		glDrawArrays(GL_TRIANGLES, 0, vertexCount);
		
		glDisableVertexAttribArray(1);
		glDisableVertexAttribArray(0);
		
		effect.unbind();
		
		glBindVertexArray(0);
	}
}