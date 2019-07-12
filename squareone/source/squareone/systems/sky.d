module squareone.systems.sky;

import moxane.core;
import moxane.graphics.renderer;

import squareone.util.cube;

import std.algorithm.searching : canFind;
import derelict.opengl3.gl3;
import containers.unrolledlist;
import dlib.math.vector : Vector3f;
import dlib.math.matrix : Matrix4f;
import dlib.math.transformation;

class SkySystem
{
	Entity skyBox;

	this(Moxane moxane)
	{
		EntityManager em = moxane.services.get!EntityManager;
		em.onEntityAdd.addCallback(&entityAddCallback);
		em.onEntityRemove.addCallback(&entityRemoveCallback);
	}

	private void entityAddCallback(OnEntityAdd e)
	{
		if(e.entity.has!SkyComponent)
		{
			synchronized(this)
			{
				if(skyBox is null)
					skyBox = e.entity;
				else throw new Exception("Error! Only one skybox entity is permitted at a time");
			}
		}
	}

	private void entityRemoveCallback(OnEntityAdd e)
	{
		synchronized(this)
			if(skyBox == e.entity)
				skyBox = null;
	}
}

class SkyRenderer : IRenderable
{
	SkySystem skySystem;

	private uint vao;
	private uint vertexBO, normalBO, texBO;

	this()
	{
		glGenVertexArrays(1, &vao);

		Vector3f[36] cubeVerts;
		Vector3f[36] cubeNorms;
		size_t i;
		foreach(dir; 0 .. 6)
		foreach(triag; 0 ..2)
		foreach(vert; 0 .. 3)
		{
			cubeVerts[i] = cubeVertices[cubeIndices[dir][triag][vert]];
			cubeNorms[i] = -cubeNormals[dir];
			i++;
		}

		glGenBuffers(1, &vertexBO);
		glGenBuffers(1, &normalBO);
		glGenBuffers(1, &texBO);
	}

	~this()
	{
		glDeleteVertexArrays(1, &vao);
	}

	void render(Renderer renderer, ref LocalContext lc, out uint drawCalls, out uint numVerts)
	{
		if(skySystem.skyBox is null) return;

		synchronized(skySystem)
		{
			glBindVertexArray(vao);
			scope(exit) glBindVertexArray(0);

			SkyComponent* sky = skySystem.skyBox.get!SkyComponent;
			if(sky is null) return;


		}
	}
}

struct SkyComponent
{
	float scale;
}