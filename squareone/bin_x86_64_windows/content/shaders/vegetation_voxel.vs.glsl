#version 400 core

layout(location = 0) in vec3 Vertex;
layout(location = 1) in ivec4 Colour;
layout(location = 2) in vec2 TexCoord;

out vec3 fWorldPos;
out vec2 fTexCoord;
flat out vec3 fColour;
flat out float fTexID;

uniform mat4 ModelViewProjection;
uniform mat4 Model;

void main() {
	gl_Position = ModelViewProjection * vec4(Vertex, 1);
	fWorldPos = (Model * vec4(Vertex, 1)).xyz;
	fTexCoord = TexCoord;
	fColour = Colour.xyz / vec3(255);
	fTexID = Colour.w;// > 128 ? 1 : 0.5;
}