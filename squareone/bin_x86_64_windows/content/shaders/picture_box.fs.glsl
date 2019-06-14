#version 400 core

in vec2 fTexCoord;

out vec4 Fragment;

uniform sampler2D Texture;

void main() {
	Fragment = texture(Texture, fTexCoord);
}