#version 400 core

layout(location = 0) in vec3 Vertex;
layout(location = 1) in vec3 Normal;

uniform mat4 ModelViewProjection;
uniform mat4 Model;

out vec3 fWorldPos;
out vec3 fVertexPos;
out vec3 fNormal;

void main()
{
	fWorldPos = (Model * vec4(Vertex, 1)).xyz;
	fVertexPos = Vertex;
	fNormal = Normal;
	gl_Position = ModelViewProjection * vec4(Vertex, 1);
}