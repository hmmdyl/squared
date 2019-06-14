#version 430 core
#extension GL_EXT_texture_array : enable

in vec3 fNormal;
flat in float fTexID;
flat in ivec4 fMeta;
in vec2 fTexCoordX;
in vec2 fTexCoordY;
in vec2 fTexCoordZ;
in vec3 fWorldPos;

layout(location = 1) out vec3 WorldPositionOut;
layout(location = 0) out vec3 DiffuseOut;
layout(location = 2) out vec3 NormalOut;

uniform sampler2DArray Diffuse;

void main() {
    vec3 n = fNormal * fNormal;
    vec4 texel = texture2DArray(Diffuse, vec3(fTexCoordX, fTexID)) * n.x +
                 texture2DArray(Diffuse, vec3(fTexCoordY, fTexID)) * n.y +
                 texture2DArray(Diffuse, vec3(fTexCoordZ, fTexID)) * n.z;

    WorldPositionOut = fWorldPos;
    DiffuseOut = texel.rgb;
    //DiffuseOut = vec3(1);
	//DiffuseOut = vec3(fMeta.x * 100);
    NormalOut = fNormal;
}