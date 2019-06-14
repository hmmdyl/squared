#version 400 core

layout(location = 0) in vec2 Vertex;

out vec2 fTexCoord;

uniform vec2 Position;
uniform vec2 Size;
uniform mat4 Projection;

void main() {
    fTexCoord = vec2(Vertex.x, 1.0 - Vertex.y);
    vec2 vert = Position + (Vertex * Size);
    gl_Position = Projection * vec4(vert, 0, 1);
}