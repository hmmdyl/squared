module squareone.common.voxel.rle;

import squareone.common.voxel;

import std.experimental.allocator.mallocator : Mallocator;
import std.exception : enforce;

@trusted:

private alias rleCountType = ushort;

ubyte[] rleCompressDualPass(const ref Voxel[] voxels) @trusted
{
	enforce(voxels.length > 0, "voxels.length must be > 0");

	rleCountType count = 1;
	rleCountType compCount = 1;
	Voxel current = voxels[0];

	foreach(Voxel item; voxels[1 .. $]) 
	{
		if(current == item && count < rleCountType.max)
			count++;
		else 
		{
			count = 1;
			compCount++;
			current = item;
		}
	}

	auto memlength = rleCountType.sizeof * compCount + Voxel.sizeof * compCount;
	ubyte[] arr = cast(ubyte[])Mallocator.instance.allocate(memlength);

	count = 1;
	current = voxels[0];

	uint meminc = 0;

	void putMemOnBuffer() 
	{
		ubyte[/*ushort.sizeof*/] cArr = (*cast(ubyte[rleCountType.sizeof]*)&count);
		foreach(int x; 0 .. rleCountType.sizeof)
			arr[meminc + x] = cArr[x];
		meminc += rleCountType.sizeof;

		ubyte[/*Voxel.sizeof*/] vArr = (*cast(ubyte[Voxel.sizeof]*)&current);
		foreach(int x; 0 .. Voxel.sizeof)
			arr[meminc + x] = vArr[x];
		meminc += Voxel.sizeof;
	}

	foreach(Voxel item; voxels[1 .. $]) 
	{
		if(current == item && count < rleCountType.max)
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
	chunk.isCompressed = true;
}

Voxel[] rleDecompressCheat(ref ubyte[] data, int numVoxels) @trusted
{
	enforce(data.length > 0, "data.length must be > 0");

	Voxel[] voxels = cast(Voxel[])Mallocator.instance.allocate(numVoxels * Voxel.sizeof);
	int voxelCount = 0;

	for(int dataCount = 0; dataCount < data.length;) 
	{
		rleCountType runlength;
		ubyte[/*ushort.sizeof*/] runlengthArr = (*cast(ubyte[rleCountType.sizeof]*)&runlength);
		runlengthArr[0 .. $] = data[dataCount .. dataCount + rleCountType.sizeof];

		if(runlength > numVoxels)
		{
			import std.stdio;
			writeln("data.length: ", data.length, " numVoxels: ", numVoxels, " runLength: ", runlength);
			throw new Exception("OUT OF BOUNDS");
		}

		Voxel current;
		ubyte[/*Voxel.sizeof*/] voxelArr = (*cast(ubyte[Voxel.sizeof]*)&current);
		voxelArr[0 .. $] = data[dataCount + rleCountType.sizeof .. dataCount + rleCountType.sizeof + Voxel.sizeof];

		dataCount += rleCountType.sizeof + Voxel.sizeof;

		foreach(int run; 0 .. runlength) 
		{
			try {
				import std.stdio;
				//writeln("data.length: ", data.length, " numVoxels: ", numVoxels, " runLength: ", runlength, " current: ", current, " run: ", run);
				voxels[voxelCount] = Voxel(current.material, current.mesh, current.materialData, current.meshData);
				voxelCount++;
			}
			catch(Throwable)
			{
				import std.stdio;
				writeln("data.length: ", data.length, " numVoxels: ", numVoxels, " runLength: ", runlength, " current: ", current, " run: ", run);
			}
		}
	}

	return voxels;
}

void decompressChunk(ICompressableVoxelBuffer vb) 
{
	Voxel[] v = rleDecompressCheat(vb.compressedData, vb.dimensionsTotal ^^ 3);
	vb.deallocateCompressedData();
	vb.voxels = v;
	vb.isCompressed = false;
}