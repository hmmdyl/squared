module squareone.voxelcontent.fluid.types;

import squareone.voxel;
import squareone.voxelcontent.fluid.processor;

import dlib.math;

enum redBits = 3;
enum redMax = (2 ^^ redBits)-1;
enum greenBits = 5;
enum greenMax = (2 ^^ greenBits)-1;
enum blueBits = 5;
enum blueMax = (2 ^^ blueBits)-1;

void setColour(Vector3f col, ref Voxel voxel)
{
	ushort red = cast(ushort)(col.x * redMax);
	red = cast(ushort)clamp(red, 0, redMax);
	ushort green = cast(ushort)clamp(cast(ushort)(col.y * greenMax), 0, greenMax);
	ushort blue = cast(ushort)clamp(cast(ushort)(col.z * blueMax), 0, blueMax);

	voxel.materialData = voxel.materialData & ~0b0001_1111_1111_1111;
	voxel.materialData = voxel.materialData | (blue << 8 | green << 3 | red);
}

Vector3f getColour(const Voxel voxel)
{
	ubyte red = voxel.materialData & 0b0111;
	ubyte green = cast(ubyte)((voxel.materialData >> 3) & 0xb0001_1111);
	ubyte blue = cast(ubyte)((voxel.materialData >> 8) & 0xb0001_1111);

	float red1 = cast(float)red / (redMax);
	float green1 = cast(float)green / (greenMax);
	float blue1 = cast(float)blue / (blueMax);

	return Vector3f(red1, green1, blue1);
}

private struct FluidVoxel
{
	Voxel voxel;
	alias voxel this;

	@property Vector3f colour() const { return getColour(voxel); }
	@property void colour(Vector3f c) { setColour(c, voxel); }
}