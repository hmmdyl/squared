#version 400 core
#extension GL_EXT_texture_array : enable

in vec3 fWorldPos;
in vec2 fTexCoord;
flat in vec3 fColour;
flat in float fTexID;

layout(location = 0) out vec3 DiffuseOut;
layout(location = 1) out vec3 WorldPositionOut;
layout(location = 2) out vec3 NormalOut;

uniform sampler2DArray Textures;

void main() {
	vec4 texel = texture2DArray(Textures, vec3(fTexCoord, fTexID));
	vec3 diffuse;

	if(texel.a < 0.3) discard;
	else if(texel.a > 0.35 && texel.a < 0.55)
		diffuse = texel.rgb;
	else if(texel.a > 0.6 && texel.a < 0.8)
		diffuse = texel.rgb * fColour;
	else diffuse = fColour;

	DiffuseOut = diffuse;

	WorldPositionOut = fWorldPos;
	NormalOut = vec3(0, 1, 0);
}