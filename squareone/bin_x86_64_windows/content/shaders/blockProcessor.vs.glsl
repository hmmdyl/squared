#version 430 core

layout(location = 0) in vec3 Vertex;
layout(location = 1) in vec3 Normal;
layout(location = 2) in ivec4 Meta;

out vec3 fNormal;
flat out float fTexID;
flat out ivec4 fMeta;
out vec2 fTexCoordX;
out vec2 fTexCoordY;
out vec2 fTexCoordZ;
out vec3 fWorldPos;

uniform mat4 ModelViewProjection;
uniform mat4 Model;
uniform mat4 ModelView;

uniform float Fit10bScale;

void main() {
    //vec3 vert = Vertex.xyz / Fit10bScale;
    vec3 vert = Vertex.xyz;
    gl_Position = ModelViewProjection * vec4(vert, 1);
    fNormal = (Normal.xyz / 1023) * 2 - 1;
    fNormal = normalize(fNormal);

    fTexCoordX = vert.zy;
    fTexCoordY = vert.xz;
    fTexCoordZ = vert.xy;

	fMeta = Meta;
    fTexID = Meta.x | (Meta.y << 8);

    fWorldPos = (ModelView * vec4(vert, 1)).xyz;
}