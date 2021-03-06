module squareone.common.voxel.smoother;

import squareone.common.voxel.voxel;
import squareone.common.voxel.resources;

@safe:

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

				/// slopes who are by themselves
				else if(nx.mesh == c.root && px.mesh != c.root && nz.mesh != c.root && pz.mesh != c.root && ny.mesh == c.root && py.mesh != c.root)	output[idx] = Voxel(voxel.material, c.slope, voxel.materialData, 0);
				else if(nz.mesh == c.root && pz.mesh != c.root && nx.mesh != c.root && px.mesh != c.root && ny.mesh == c.root && py.mesh != c.root)	output[idx] = Voxel(voxel.material, c.slope, voxel.materialData, 1);
				else if(px.mesh == c.root && nx.mesh != c.root && nz.mesh != c.root && pz.mesh != c.root && ny.mesh == c.root && py.mesh != c.root)	output[idx] = Voxel(voxel.material, c.slope, voxel.materialData, 2);
				else if(pz.mesh == c.root && nz.mesh != c.root && nx.mesh != c.root && px.mesh != c.root && ny.mesh == c.root && py.mesh != c.root)	output[idx] = Voxel(voxel.material, c.slope, voxel.materialData, 3);

				else if(nx.mesh == c.root && nz.mesh == c.root && px.mesh != c.root && pz.mesh != c.root && py.mesh != c.root)	output[idx] = Voxel(voxel.material, c.tetrahedron, voxel.materialData, 0);
				else if(px.mesh == c.root && nz.mesh == c.root && nx.mesh != c.root && pz.mesh != c.root && py.mesh != c.root)	output[idx] = Voxel(voxel.material, c.tetrahedron, voxel.materialData, 1);
				else if(px.mesh == c.root && pz.mesh == c.root && nx.mesh != c.root && nz.mesh != c.root && py.mesh != c.root)	output[idx] = Voxel(voxel.material, c.tetrahedron, voxel.materialData, 2);
				else if(nx.mesh == c.root && pz.mesh == c.root && px.mesh != c.root && nz.mesh != c.root && py.mesh != c.root)	output[idx] = Voxel(voxel.material, c.tetrahedron, voxel.materialData, 3);

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
					//output[idx] = voxel;
					continue;
				}
				if(output[idx].mesh != c.root) continue;

				Voxel ny = input[fltIdx(x, y - 1, z, dimensions)];

				if(ny.mesh != c.root)
				{
					//output[idx] = voxel;
					continue;
				}

				Voxel nx = input[fltIdx(x - 1, y, z, dimensions)];
				Voxel nxO = output[fltIdx(x - 1, y, z, dimensions)];
				Voxel px = input[fltIdx(x + 1, y, z, dimensions)];
				Voxel pxO = output[fltIdx(x + 1, y, z, dimensions)];
				Voxel nz = input[fltIdx(x, y, z - 1, dimensions)];
				Voxel nzO = output[fltIdx(x, y, z - 1, dimensions)];
				Voxel pz = input[fltIdx(x, y, z + 1, dimensions)];
				Voxel pzO = output[fltIdx(x, y, z + 1, dimensions)];
				Voxel py = input[fltIdx(x, y + 1, z, dimensions)];

				Voxel nxNz = input[fltIdx(x - 1, y, z - 1, dimensions)];
				Voxel nxPz = input[fltIdx(x - 1, y, z + 1, dimensions)];
				Voxel pxNz = input[fltIdx(x + 1, y, z - 1, dimensions)];
				Voxel pxPz = input[fltIdx(x + 1, y, z + 1, dimensions)];

				if(nx.mesh == c.root && nz.mesh == c.root && (pxO.mesh == c.tetrahedron || pxO.mesh == c.slope) && (pzO.mesh == c.tetrahedron || pzO.mesh == c.slope) && pxPz.mesh != c.root)
					output[idx] = Voxel(voxel.material, c.antiTetrahedron, voxel.materialData, 0);
				else if(nx.mesh == c.root && nz.mesh == c.root && (((pxO.mesh == c.tetrahedron || pxO.mesh == c.slope) && pzO.mesh == c.inv) || ((pzO.mesh == c.tetrahedron || pzO.mesh == c.slope) && pxO.mesh == c.inv)) && pxPz.mesh != c.root)
					output[idx] = Voxel(voxel.material, c.antiTetrahedron, voxel.materialData, 0);

				else if(px.mesh == c.root && nz.mesh == c.root && (nxO.mesh == c.tetrahedron || nxO.mesh == c.slope) && (pzO.mesh == c.tetrahedron || pzO.mesh == c.slope) && nxPz.mesh != c.root)
					output[idx] = Voxel(voxel.material, c.antiTetrahedron, voxel.materialData, 1);
				else if(px.mesh == c.root && nz.mesh == c.root && (((nxO.mesh == c.tetrahedron || nxO.mesh == c.slope) && pzO.mesh == c.inv) || ((pzO.mesh == c.tetrahedron || pzO.mesh == c.slope) && nxO.mesh == c.inv)) && nxPz.mesh != c.root)
					output[idx] = Voxel(voxel.material, c.antiTetrahedron, voxel.materialData, 1);

				else if(px.mesh == c.root && pz.mesh == c.root && (nxO.mesh == c.tetrahedron || nxO.mesh == c.slope) && (nzO.mesh == c.tetrahedron || nzO.mesh == c.slope) && nxNz.mesh != c.root)
					output[idx] = Voxel(voxel.material, c.antiTetrahedron, voxel.materialData, 2);
				else if(px.mesh == c.root && pz.mesh == c.root && (((nxO.mesh == c.tetrahedron || nxO.mesh == c.slope) && nzO.mesh == c.inv) || ((nzO.mesh == c.tetrahedron || nzO.mesh == c.slope) && nxO.mesh == c.inv)) && nxNz.mesh != c.root)
					output[idx] = Voxel(voxel.material, c.antiTetrahedron, voxel.materialData, 2);

				else if(nx.mesh == c.root && pz.mesh == c.root && (pxO.mesh == c.tetrahedron || pxO.mesh == c.slope) && (nzO.mesh == c.tetrahedron || nzO.mesh == c.slope) && pxNz.mesh != c.root)
					output[idx] = Voxel(voxel.material, c.antiTetrahedron, voxel.materialData, 3);
				else if(nx.mesh == c.root && pz.mesh == c.root && (((pxO.mesh == c.tetrahedron || pxO.mesh == c.slope) && nzO.mesh == c.inv) || ((nzO.mesh == c.tetrahedron || nzO.mesh == c.slope) && pxO.mesh == c.inv)) && pxNz.mesh != c.root)
					output[idx] = Voxel(voxel.material, c.antiTetrahedron, voxel.materialData, 3);

				/+if(nx.mesh == c.root && nz.mesh == c.root && px.mesh == c.root && pz.mesh == c.root && py.mesh != c.root) 
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
				}+/

			}
}