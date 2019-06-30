module squareone.voxelcontent.vegetation.types;

import squareone.voxel;

import dlib.math.vector;
import dlib.math.utils;

enum MeshType
{
	other,
	grassHalf,
	grass,
	grass2,
	grass4,
	grass8,
	flowerShort,
	flower,
}

enum flowerShortHeight = 1; // block

float meshTypeToBlockHeight(const MeshType mt)
{
	final switch(mt) with(MeshType)
	{
		case other: return float.nan;
		case grassHalf: return 0.5f;
		case grass: return 1f;
		case grass2: return 2f;
		case grass4: return 4f;
		case grass8: return 8f;
		case flowerShort: return 1f;
		case flower: return 2f;
	}
}

bool isGrass(const MeshType mt)
{
	with(MeshType)
		return mt == grassHalf || mt == grass || mt == grass2 || mt == grass4 || mt == grass8;
}

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

Vector3f extractColour(const Voxel v)
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

ubyte getGrassOffset(const Voxel v)
{
	return ((v.meshData >> 17) & 0x3);
}

void setGrassOffset(ubyte o, Voxel* v)
{
	v.meshData = v.meshData & ~(0x3 << 17);
	v.meshData = v.meshData | ((o & 0x3) << 17);
}

struct VegetationVoxel
{
	private Voxel voxel;
	alias voxel this;

	@property Vector3f colour() { return extractColour(voxel); }
	@property void colour(Vector3f c) { insertColour(c, &voxel); }
	@property FlowerRotation flowerRotation() { return getFlowerRotation(voxel); }
	@property void flowerRotation(FlowerRotation fr) { setFlowerRotation(fr, &voxel); }
	@property ubyte grassOffset() { return getGrassOffset(voxel); }
	@property void grassOffset(ubyte o) { setGrassOffset(o, &voxel); }
}

interface IVegetationVoxelMaterial : IVoxelMaterial
{
	void loadTextures();

	@property ubyte grassTexture() const;
	@property ubyte flowerStorkTexture() const;
	@property ubyte flowerHeadTexture() const;
	@property ubyte flowerLeafTexture() const;
}

struct RenderData
{
	uint vertex, colour, texCoords;
	ushort vertexCount;

	void create()
	{
		import derelict.opengl3.gl3 : glGenBuffers;
		glGenBuffers(1, &vertex);
		glGenBuffers(1, &colour);
		glGenBuffers(1, &texCoords);
		vertexCount = 0;
	}

	void destroy()
	{
		import derelict.opengl3.gl3 : glDeleteBuffers;
		glDeleteBuffers(1, &vertex);
		glDeleteBuffers(1, &colour);
		glDeleteBuffers(1, &texCoords);
		vertexCount = 0;
	}
}