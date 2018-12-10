module square.one.isomesher.mc;

import square.one.terrain.chunk;
import square.one.terrain.voxel;

import square.one.isomesher.mctables;

import gfm.math;

import std.typecons;
import std.math;

immutable vec3i[7] accessors = 
[
	vec3i(1, 0, 0),
	vec3i(1, 0, 1),
	vec3i(0, 0, 1),
	vec3i(0, 1, 0),
	vec3i(1, 1, 0),
	vec3i(1, 1, 1),
	vec3i(0, 1, 1)
];

alias PnPair = Tuple!(vec3f, "vertex", vec3f, "normal");

private PnPair interp(float d1, float d2,
					vec3f p1, vec3f p2,
					vec3f n1, vec3f n2)
{
	if(abs(isolevel - d1) < 0.0001) return PnPair(p1, n1);
	if(abs(isolevel - d2) < 0.0001) return PnPair(p2, n2);
	if(abs(d1 -d2) < 0.0001) return (p1, n1);

	float mu = (isolevel - d1) / (d2 - d1);
	return PnPair(p1 + mu * (p2 - p1), n1 + mu * (n2 - n1));
}

struct Cell
{
	vec3f[8] densities;
	vec3f[8] points;
	vec3f[8] normals;

	this(vec3f[8] densities, vec3f[8] points, vec3f[8] normals)
	{
		this.densities = densities;
		this.points = points;
		this.normals = normals;
	}
}

void meshCell(const Cell c, const float isolevel, out vec3f[15] finalVertices, out vec3f[15] finalNormals, out int vertexCount)
{
	ubyte edgeType;
	if(c.densities[0] < isolevel) edgeType |= 1;
	if(c.densities[1] < isolevel) edgeType |= 2;
	if(c.densities[2] < isolevel) edgeType |= 4;
	if(c.densities[3] < isolevel) edgeType |= 8;
	if(c.densities[4] < isolevel) edgeType |= 16;
	if(c.densities[5] < isolevel) edgeType |= 32;
	if(c.densities[6] < isolevel) edgeType |= 64;
	if(c.densities[7] < isolevel) edgeType |= 128;

	const int edgeIndex = edgeTable[edgeType];
	if(edgeIndex == 0 || edgeIndex == 255) return;

	PnPair[12] ipn;
	
	if((edgeIndex & 1) > 0) ipn[0] = interp(voxels[0].density, voxels[1].density, points[0], points[1], normals[0], normals[1]);
    if((edgeIndex & 2) > 0) ipn[1] = interp(voxels[1].density, voxels[2].density, points[1], points[2], normals[1], normals[2]);
    if((edgeIndex & 4) > 0) ipn[2] = interp(voxels[2].density, voxels[3].density, points[2], points[3], normals[2], normals[3]);
    if((edgeIndex & 8) > 0) ipn[3] = interp(voxels[3].density, voxels[0].density, points[3], points[0], normals[3], normals[0]);
    if((edgeIndex & 16) > 0) ipn[4] = interp(voxels[4].density, voxels[5].density, points[4], points[5], normals[4], normals[5]);
    if((edgeIndex & 32) > 0) ipn[5] = interp(voxels[5].density, voxels[6].density, points[5], points[6], normals[5], normals[6]);
    if((edgeIndex & 64) > 0) ipn[6] = interp(voxels[6].density, voxels[7].density, points[6], points[7], normals[6], normals[7]);
    if((edgeIndex & 128) > 0) ipn[7] = interp(voxels[7].density, voxels[4].density, points[7], points[4], normals[7], normals[4]);
    if((edgeIndex & 256) > 0) ipn[8] = interp(voxels[0].density, voxels[4].density, points[0], points[4], normals[0], normals[4]);
    if((edgeIndex & 512) > 0) ipn[9] = interp(voxels[1].density, voxels[5].density, points[1], points[5], normals[1], normals[5]);
    if((edgeIndex & 1024) > 0) ipn[10] = interp(voxels[2].density, voxels[6].density, points[2], points[6], normals[2], normals[6]);
    if((edgeIndex & 2048) > 0) ipn[11] = interp(voxels[3].density, voxels[7].density, points[3], points[7], normals[3], normals[7]);

	vertexCount = 0;

	for(; triangleTable[edgeType][vertexCount] != -1; vertexCount++)
	{
		const int index = triangleTable[edgeType][vertexCount];
		finalVertices[vertexCount] = ipn.vertex;
		finalNormals[vertexCount] = ipn.normal.normalized();
	}
}