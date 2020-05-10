module squareone.common.content.voxel.vegetation.types;

import squareone.common.content.voxel.vegetation.processor;
import squareone.common.voxel;
import dlib.math;

enum MeshType
{
	other,
	grass,
	flowerShort,
	flower,
	leaf
}

enum flowerShortHeight = 1; // block

interface IVegetationVoxelMesh : IVoxelMesh
{
	@property MeshType meshType() const;
	void generateOtherMesh();
}

interface IVegetationVoxelTexture : IVoxelContent
{
	@property ubyte id() const;
	@property void id(ubyte);

	@property string file();
}

Vector3f extractColour(immutable Voxel v)
{
	uint col = v.materialData & 0x3_FFFF;
	uint r = col & 0x3F;
	uint g = (col >> 6) & 0x3F;
	uint b = (col >> 12) & 0x3F;
	return Vector3f(r / 63f, g / 63f, b / 63f);
}

void insertColour(Vector3f col, Voxel* v) {
	v.materialData = v.materialData & ~0x3_FFFF;
	uint r = clamp(cast(uint)(col.x * 63), 0, 63);
	uint g = clamp(cast(uint)(col.y * 63), 0, 63);
	uint b = clamp(cast(uint)(col.z * 63), 0, 63);
	uint f = (b << 12) | (g << 6) | r;
	v.materialData = v.materialData | f;
}

enum FlowerRotation : ubyte {
	nz = 0,
	nzpx = 1,
	px = 2,
	pxpz = 3,
	pz = 4,
	nxpz = 5,
	nx = 6,
	nxnz = 7
}

FlowerRotation getFlowerRotation(Voxel v) {
	ubyte twobits = (v.materialData >> 18) & 0x3;
	ubyte onebit = (v.meshData >> 19) & 0x1;
	int total = (onebit << 2) | twobits;
	return cast(FlowerRotation)total;
}

void setFlowerRotation(FlowerRotation fr, Voxel* v) {
	ubyte twobits = cast(ubyte)fr & 0x3;
	ubyte onebit = ((cast(ubyte)fr) >> 2) & 0x1;
	v.materialData = v.materialData & ~(0x3 << 18);
	v.materialData = v.materialData | (twobits << 18);
	v.meshData = v.meshData & ~(0x1 << 19);
	v.meshData = v.meshData | (onebit << 19);
}

ubyte getGrassOffset(immutable Voxel v)
{
	return ((v.meshData >> 16) & 0x7);
}

void setGrassOffset(immutable ubyte o, Voxel* v)
{
	v.meshData = v.meshData & ~(0x7 << 16);
	v.meshData = v.meshData | ((o & 0x7) << 16);
}

float offsetToHeight(immutable ubyte offset) pure
{
	switch(offset)
	{
		case 0: return 0f;
		case 1: return 0.05f;
		case 2: return 0.1f;
		case 3: return 0.15f;
		case 4: return 0.2f;
		case 5: return -0.05f;
		case 6: return -0.125f;
		case 7: return -0.2f;
		default: return float.nan;
	}
}

struct GrassVoxel
{
	Voxel v;
	alias v this;

	this(Voxel voxel) {this.v = voxel;}

	@property Vector3f colour() const { return extractColour(v); }
	@property void colour(Vector3f col) { insertColour(col, &v); }

	@property ubyte offset() const { return getGrassOffset(v); }
	@property void offset(ubyte off) { setGrassOffset(off, &v); }

	@property float heightOffset() const { return offsetToHeight(offset()); }

	@property float blockHeight() const { return getBlockHeight(v); }
	@property ubyte blockHeightCode() const { return getBlockHeightCode(v); }
	@property void blockHeightCode(ubyte n) { setBlockHeightCode(n, &v); }
}

float grassHeightCodeToBlockHeight(immutable ubyte d) pure
{
	final switch(d)
	{
		case 0: return 0.5f;
		case 1: return 1f;
		case 2: return 1.5f;
		case 3: return 2f;
		case 4: return 3f;
		case 5: return 4f;
		case 6: return 6f;
		case 7: return 8f;
	}
}

ubyte getBlockHeightCode(immutable Voxel v) { return ((v.meshData >> 13) & 0x7); }
void setBlockHeightCode(immutable ubyte h, Voxel* v)
{
	v.meshData = v.meshData & ~(0x7 << 13);
	v.meshData = v.meshData | ((h & 0x7) << 13);
}

float getBlockHeight(immutable Voxel v) { return grassHeightCodeToBlockHeight(getBlockHeightCode(v)); }

struct VegetationVoxel
{
	Voxel v;
	alias v this;

	this(Voxel v)
	{
		this.v = v;
	}

	@property Vector3f colour() { return extractColour(v); }
	@property void colour(Vector3f c) { insertColour(c, &v); }
	@property FlowerRotation flowerRotation() { return getFlowerRotation(v); }
	@property void flowerRotation(FlowerRotation fr) { setFlowerRotation(fr, &v); }
	@property ubyte grassOffset() { return getGrassOffset(v); }
	@property void grassOffset(ubyte o) { setGrassOffset(o, &v); }
}

interface IVegetationVoxelMaterial : IVoxelMaterial
{
	void loadTextures(VegetationProcessorBase);

	@property ubyte grassTexture() const;
	@property ubyte flowerStorkTexture() const;
	@property ubyte flowerHeadTexture() const;
	@property ubyte flowerLeafTexture() const;
}

struct LeafVoxel
{
	Voxel v;
	alias v this;
	this(Voxel v) { this.v = v; }

	@property Vector3f colour() const { return extractColour(v); }
	@property void colour(Vector3f c) { insertColour(c, &v); }
	@property FlowerRotation rotation() const { return getFlowerRotation(v); }
	@property void rotation(FlowerRotation f) { setFlowerRotation(f, &v); }

	enum Direction
	{
		negative90,
		negative45,
		zero,
		positive45
	}

	static Direction getDirection(immutable Voxel v) { return cast(Direction)((v.meshData >> 17) & 0x3); }
	static void setDirection(ref Voxel v, Direction dir) { v.meshData = v.meshData & ~(0x3 << 17); v.meshData = v.meshData | ((cast(int)dir & 0x3) << 17); }

	@property Direction direction() const { return getDirection(v); }
	@property void direction(Direction u) { setDirection(v, u); }
}

struct RenderData
{
	uint vertex, colour, texCoords/+, normal+/;
	ushort vertexCount;

	// compression
	float chunkMax;
	float fit10BitScale;
	float offset;

	void create()
	{
		import derelict.opengl3.gl3 : glGenBuffers;
		glGenBuffers(1, &vertex);
		glGenBuffers(1, &colour);
		glGenBuffers(1, &texCoords);
		//glGenBuffers(1, &normal);
		vertexCount = 0;
	}

	void destroy()
	{
		import derelict.opengl3.gl3 : glDeleteBuffers;
		glDeleteBuffers(1, &vertex);
		glDeleteBuffers(1, &colour);
		glDeleteBuffers(1, &texCoords);
		//glDeleteBuffers(1, &normal);
		vertexCount = 0;
	}
}