#version 400 core

uniform vec4 Colour;

out vec4 Fragment;

void main() {
	Fragment = Colour;
}