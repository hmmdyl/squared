module squareone.voxelutils.smoother;

import squareone.voxel;

struct SmootherConfig
{
	MeshID root;

	MeshID inv,
		cube,
		slope,
		tetrahedron,
		antiTetrahedron,
		horizontalSlope;
}

pragma(inline, true)
private int fltIdx(const int x, const int y, const int z, const int dimensions)
{ return x + dimensions * (y + dimensions * z); }

void smoother(Voxel[] input, Voxel[] output, const int start, const int end, const int dimensions, const SmootherConfig config)
{
	pass0(input, output, start, end, dimensions, config);
	pass1(input, output, start, end, dimensions, config);
}

private void pass0(Voxel[] input, Voxel[] output, const int start, const int end, const int dimensions, const SmootherConfig c)
{
	foreach(z; start .. dimensions)
	foreach(y; start .. dimensions)
	foreach(x; start .. dimensions)
	{
		int idx = fltIdx(x, y, z, dimensions);
		Voxel voxel = input[idx];
		if(voxel.mesh != c.root) 
		{
			output[idx] = voxel;
			continue;
		}

		Voxel ny = input[fltIdx(x, y - 1, z, dimensions)];

		if(ny.mesh != c.root)
		{
			output[idx] = voxel;
			continue;
		}

		Voxel nx = input[fltIdx(x - 1, y, z, dimensions)];
		Voxel px = input[fltIdx(x + 1, y, z, dimensions)];
		Voxel nz = input[fltIdx(x, y, z - 1, dimensions)];
		Voxel pz = input[fltIdx(x, y, z + 1, dimensions)];
		Voxel py = input[fltIdx(x, y + 1, z, dimensions)];

		Voxel nxNz = input[fltIdx(x - 1, y, z - 1, dimensions)];
		Voxel nxPz = input[fltIdx(x - 1, y, z + 1, dimensions)];
		Voxel pxNz = input[fltIdx(x + 1, y, z - 1, dimensions)];
		Voxel pxPz = input[fltIdx(x + 1, y, z + 1, dimensions)];

		if(nx.mesh == c.root && px.mesh != c.root && nz.mesh == c.root && pz.mesh == c.root && py.mesh != c.root)		output[idx] = Voxel(voxel.material, c.slope, voxel.materialData, 0);
		else if(px.mesh == c.root && nx.mesh != c.root && nz.mesh == c.root && pz.mesh == c.root && py.mesh != c.root)	output[idx] = Voxel(voxel.material, c.slope, voxel.materialData, 2);
		else if(nz.mesh == c.root && pz.mesh != c.root && nx.mesh == c.root && px.mesh == c.root && py.mesh != c.root)	output[idx] = Voxel(voxel.material, c.slope, voxel.materialData, 1);
		else if(pz.mesh == c.root && nz.mesh != c.root && nx.mesh == c.root && px.mesh == c.root && py.mesh != c.root)	output[idx] = Voxel(voxel.material, c.slope, voxel.materialData, 3);

		else if(nx.mesh == c.root && nz.mesh == c.root && px.mesh != c.root && pz.mesh != c.root && py.mesh != c.root) output[idx] = Voxel(voxel.material, c.tetrahedron, voxel.materialData, 0);
		else if(px.mesh == c.root && nz.mesh == c.root && nx.mesh != c.root && pz.mesh != c.root && py.mesh != c.root) output[idx] = Voxel(voxel.material, c.tetrahedron, voxel.materialData, 1);
		else if(px.mesh == c.root && pz.mesh == c.root && nx.mesh != c.root && nz.mesh != c.root && py.mesh != c.root) output[idx] = Voxel(voxel.material, c.tetrahedron, voxel.materialData, 2);
		else if(nx.mesh == c.root && pz.mesh == c.root && px.mesh != c.root && nz.mesh != c.root && py.mesh != c.root) output[idx] = Voxel(voxel.material, c.tetrahedron, voxel.materialData, 3);

		else if(nx.mesh == c.root && pz.mesh == c.root && px.mesh != c.root && nz.mesh != c.root && pxNz.mesh != c.root) output[idx] = Voxel(voxel.material, c.horizontalSlope, voxel.materialData, 0);
		else if(nx.mesh == c.root && nz.mesh == c.root && px.mesh != c.root && pz.mesh != c.root && pxPz.mesh != c.root) output[idx] = Voxel(voxel.material, c.horizontalSlope, voxel.materialData, 1);
		else if(px.mesh == c.root && nz.mesh == c.root && nx.mesh != c.root && pz.mesh != c.root && nxPz.mesh != c.root) output[idx] = Voxel(voxel.material, c.horizontalSlope, voxel.materialData, 2);
		else if(px.mesh == c.root && pz.mesh == c.root && nx.mesh != c.root && nz.mesh != c.root && nxNz.mesh != c.root) output[idx] = Voxel(voxel.material, c.horizontalSlope, voxel.materialData, 3);

		else output[idx] = voxel;
	}
}

private void pass1(Voxel[] input, Voxel[] output, const int start, const int end, const int dimensions, const SmootherConfig c)
{
	foreach(z; start .. dimensions)
	foreach(y; start .. dimensions)
	foreach(x; start .. dimensions)
	{
		int idx = fltIdx(x, y, z, dimensions);
		Voxel voxel = input[idx];
		if(voxel.mesh != c.root) 
		{
			output[idx] = voxel;
			continue;
		}

		Voxel ny = input[fltIdx(x, y - 1, z, dimensions)];

		if(ny.mesh != c.root)
		{
			output[idx] = voxel;
			continue;
		}

		Voxel nx = input[fltIdx(x - 1, y, z, dimensions)];
		Voxel px = input[fltIdx(x + 1, y, z, dimensions)];
		Voxel nz = input[fltIdx(x, y, z - 1, dimensions)];
		Voxel pz = input[fltIdx(x, y, z + 1, dimensions)];
		Voxel py = input[fltIdx(x, y + 1, z, dimensions)];

		Voxel nxNz = input[fltIdx(x - 1, y, z - 1, dimensions)];
		Voxel nxPz = input[fltIdx(x - 1, y, z + 1, dimensions)];
		Voxel pxNz = input[fltIdx(x + 1, y, z - 1, dimensions)];
		Voxel pxPz = input[fltIdx(x + 1, y, z + 1, dimensions)];

		if(nx.mesh == c.root && nz.mesh == c.root && px.mesh == c.root && pz.mesh == c.root) 
		{
			if(pxPz.mesh != c.root)
				output[idx] = Voxel(voxel.material, c.antiTetrahedron, voxel.materialData, 0);
			else if(nxPz.mesh != c.root)
				output[idx] = Voxel(voxel.material, c.antiTetrahedron, voxel.materialData, 1);
			else if(nxNz.mesh != c.root)
				output[idx] = Voxel(voxel.material, c.antiTetrahedron, voxel.materialData, 2);
			else if(pxNz.mesh != c.root)
				output[idx] = Voxel(voxel.material, c.antiTetrahedron, voxel.materialData, 3);
			else output[idx] = voxel;
		}

	}
}