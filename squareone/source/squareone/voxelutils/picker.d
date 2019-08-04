module squareone.voxelutils.picker;

import squareone.terrain.basic.chunk;
import squareone.terrain.basic.manager;
import squareone.voxel;
import dlib.math;
import std.math;
import optional;

struct PickResult
{
	Voxel voxel;
	BlockPosition blockPosition;
	Vector3f realPosition;
	VoxelSide side;
}

PickResult pick(Vector3f origin, Vector3f originRot, BasicTerrainManager m, const int maxDistance, const ushort materialIgnore)
{
	originRot.x = degtorad(originRot.x);
	originRot.y = degtorad(originRot.y);

	Vector3f dir;
	dir.x = sin(-originRot.y) * cos(-originRot.x);
	dir.y = sin(originRot.x);
	dir.z = cos(-originRot.y) * cos(-originRot.x);

	Vector3f prev = origin;
	Vector3f curr = origin;

	BlockPosition voxelPos;

	foreach(i; 0 .. maxDistance * 10)
	{
		prev = curr;
		curr += (-dir * 0.1f);

		voxelPos = ChunkPosition.realCoordToBlockPos(curr);

		Optional!Voxel vox;
		vox = m.voxel.get(voxelPos.x, voxelPos.y, voxelPos.z);
		if(vox == none) return PickResult();

		if((*unwrap(vox)).material != materialIgnore)
			break;
	}

	PickResult result;
	result.realPosition = curr;
	result.blockPosition = voxelPos;

	Optional!Voxel vox;
	/*do*/ vox = m.voxel.get(voxelPos.x, voxelPos.y, voxelPos.z);
	if(vox == none) return PickResult();

	BlockPosition voxelPrev = ChunkPosition.realCoordToBlockPos(prev);

	if(voxelPrev.x > voxelPos.x) result.side = VoxelSide.px;
	else if(voxelPrev.x < voxelPos.x) result.side = VoxelSide.nx;
	else if(voxelPrev.y > voxelPos.y) result.side = VoxelSide.py;
	else if(voxelPrev.y < voxelPos.y) result.side = VoxelSide.ny;
	else if(voxelPrev.z > voxelPos.z) result.side = VoxelSide.pz;
	else if(voxelPrev.z < voxelPos.z) result.side = VoxelSide.nz;

	result.voxel = *unwrap(vox);

	return result;
}