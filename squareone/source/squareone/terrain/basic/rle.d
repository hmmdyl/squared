module squareone.terrain.basic.rle;

import squareone.voxel.voxel;
import squareone.voxel.chunk;

import std.experimental.allocator.mallocator : Mallocator;
import std.exception : enforce;

ubyte[] rleCompressDualPass(const ref Voxel[] voxels) @trusted
{
	enforce(voxels.length > 0, "voxels.length must be > 0");

	ushort count = 1;
	ushort compCount = 1;
	Voxel current = voxels[0];

	foreach(Voxel item; voxels[1 .. $]) 
	{
		if(current == item && count < ushort.max)
			count++;
		else 
		{
			count = 1;
			compCount++;
			current = item;
		}
	}

	uint memlength = ushort.sizeof * compCount + Voxel.sizeof * compCount;
	ubyte[] arr = cast(ubyte[])Mallocator.instance.allocate(memlength);

	count = 1;
	current = voxels[0];

	uint meminc = 0;

	void putMemOnBuffer() 
	{
		ubyte[/*ushort.sizeof*/] cArr = (*cast(ubyte[ushort.sizeof]*)&count);
		foreach(int x; 0 .. ushort.sizeof)
			arr[meminc + x] = cArr[x];
		meminc += ushort.sizeof;

		ubyte[/*Voxel.sizeof*/] vArr = (*cast(ubyte[Voxel.sizeof]*)&current);
		foreach(int x; 0 .. Voxel.sizeof)
			arr[meminc + x] = vArr[x];
		meminc += Voxel.sizeof;
	}

	foreach(Voxel item; voxels[1 .. $]) 
	{
		if(current == item && count < ushort.max)
			count++;
		else 
		{
			putMemOnBuffer();

			count = 1;
			current = item;
		}
	}

	putMemOnBuffer();

	return arr;
}

void compressChunk(ICompressableVoxelBuffer chunk)
{
	ubyte[] compressedData = rleCompressDualPass(chunk.voxels);
	chunk.deallocateVoxelData();
	chunk.compressedData = compressedData;
}

Voxel[] rleDecompressCheat(ref ubyte[] data, int numVoxels) @trusted
{
	enforce(data.length > 0, "data.length must be > 0");

	Voxel[] voxels = cast(Voxel[])Mallocator.instance.allocate(numVoxels * Voxel.sizeof);
	int voxelCount = 0;

	for(int dataCount = 0; dataCount < data.length; dataCount++) 
	{
		ushort runlength;
		ubyte[/*ushort.sizeof*/] runlengthArr = (*cast(ubyte[ushort.sizeof]*)&runlength);
		runlengthArr[0 .. $] = data[dataCount .. dataCount + 2];

		Voxel current;
		ubyte[/*Voxel.sizeof*/] voxelArr = (*cast(ubyte[Voxel.sizeof]*)&current);
		voxelArr[0 .. $] = data[dataCount + 2 .. dataCount + 10];

		dataCount += 10;

		foreach(int run; 0 .. runlength) 
		{
			voxels[voxelCount] = Voxel(current.material, current.mesh, current.materialData, current.meshData);
			voxelCount++;
		}
	}

	return voxels;
}

void decompressChunk(ICompressableVoxelBuffer vb) 
{
	Voxel[] v = rleDecompressCheat(vb.compressedData, vb.dimensionsTotal);
	vb.deallocateCompressedData();
	vb.voxels = v;
}