#version 400 core

layout(location = 0) in vec2 Vertex;

uniform vec2 Position;
uniform vec2 Size;
uniform mat4 ModelViewProjection;

void main() {
	vec2 vert = Position + (Vertex * Size);
	gl_Position = ModelViewProjection * vec4(vert, 0, 1);
}