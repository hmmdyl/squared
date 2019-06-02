module square.one.isomesher.mc;

import square.one.terrain.chunk;
import square.one.terrain.voxel;

import square.one.isomesher.mctables;

import dlib.math;

import std.typecons;
import std.math;

immutable Vector3i[7] accessors = 
[
	Vector3i(1, 0, 0),
	Vector3i(1, 0, 1),
	Vector3i(0, 0, 1),
	Vector3i(0, 1, 0),
	Vector3i(1, 1, 0),
	Vector3i(1, 1, 1),
	Vector3i(0, 1, 1)
];

alias PnPair = Tuple!(Vector3f, "vertex", Vector3f, "normal");

enum float isolevel = 0.5f;

private PnPair interp(float d1, float d2,
					Vector3f p1, Vector3f p2,
					Vector3f n1, Vector3f n2)
{
	if(abs(isolevel - d1) < 0.0001) return PnPair(p1, n1);
	if(abs(isolevel - d2) < 0.0001) return PnPair(p2, n2);
	if(abs(d1 - d2) < 0.0001) return PnPair(p1, n1);

	float mu = (isolevel - d1) / (d2 - d1);
	return PnPair(p1 + mu * (p2 - p1), n1 + mu * (n2 - n1));
}

struct Cell
{
	float[8] densities;
	Vector3f[8] points;
	Vector3f[8] normals;

	this(float[8] densities, Vector3f[8] points, Vector3f[8] normals)
	{
		this.densities = densities;
		this.points = points;
		this.normals = normals;
	}
}

void meshCell(const Cell c, const float isolevel, out Vector3f[15] finalVertices, out Vector3f[15] finalNormals, out int vertexCount)
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
	
	if((edgeIndex & 1) > 0) ipn[0] = interp(c.densities[0], c.densities[1], c.points[0], c.points[1], c.normals[0], c.normals[1]);
    if((edgeIndex & 2) > 0) ipn[1] = interp(c.densities[1], c.densities[2], c.points[1], c.points[2], c.normals[1], c.normals[2]);
    if((edgeIndex & 4) > 0) ipn[2] = interp(c.densities[2], c.densities[3], c.points[2], c.points[3], c.normals[2], c.normals[3]);
    if((edgeIndex & 8) > 0) ipn[3] = interp(c.densities[3], c.densities[0], c.points[3], c.points[0], c.normals[3], c.normals[0]);
    if((edgeIndex & 16) > 0) ipn[4] = interp(c.densities[4], c.densities[5], c.points[4], c.points[5], c.normals[4], c.normals[5]);
    if((edgeIndex & 32) > 0) ipn[5] = interp(c.densities[5], c.densities[6], c.points[5], c.points[6], c.normals[5], c.normals[6]);
    if((edgeIndex & 64) > 0) ipn[6] = interp(c.densities[6], c.densities[7], c.points[6], c.points[7], c.normals[6], c.normals[7]);
    if((edgeIndex & 128) > 0) ipn[7] = interp(c.densities[7], c.densities[4], c.points[7], c.points[4], c.normals[7], c.normals[4]);
    if((edgeIndex & 256) > 0) ipn[8] = interp(c.densities[0], c.densities[4], c.points[0], c.points[4], c.normals[0], c.normals[4]);
    if((edgeIndex & 512) > 0) ipn[9] = interp(c.densities[1], c.densities[5], c.points[1], c.points[5], c.normals[1], c.normals[5]);
    if((edgeIndex & 1024) > 0) ipn[10] = interp(c.densities[2], c.densities[6], c.points[2], c.points[6], c.normals[2], c.normals[6]);
    if((edgeIndex & 2048) > 0) ipn[11] = interp(c.densities[3], c.densities[7], c.points[3], c.points[7], c.normals[3], c.normals[7]);

	vertexCount = 0;

	for(; triangleTable[edgeType][vertexCount] != -1; vertexCount++)
	{
		const int index = triangleTable[edgeType][vertexCount];
		//finalVertices[vertexCount] = ipn.vertex;
		//finalNormals[vertexCount] = ipn.normal.normalized();
	}
}