module squareone.terrain.basic.picker;

import squareone.terrain.basic.chunk;
import squareone.terrain.basic.manager;
import squareone.voxel;
import dlib.math;
import std.math : sin, cos;
import std.typecons : Tuple, tuple;
import moxane.utils.maybe : Maybe;

struct PickResult
{
	bool got;
	Voxel voxel;
	BlockPosition blockPosition;
	Vector3f realPosition;
	VoxelSide side;

	this(bool got) { this.got = got; }
}

struct PickerIgnore
{
	MaterialID[] materials;
	MeshID[] meshes;
	Tuple!(MaterialID, MeshID)[] combinations;

	this(MaterialID[] materials, MeshID[] meshes, Tuple!(MaterialID, MeshID)[] combinations = null)
	{ this.materials = materials; this.meshes = meshes; this.combinations = combinations; }
}

PickResult pick(Vector3f origin, Vector3f originRot, BasicTerrainManager m, const int maxDistance, const PickerIgnore ignore)
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

	bool isIgnore(Voxel v)
	{
		if(ignore.materials !is null)
			foreach(MaterialID material; ignore.materials)
				if(v.material == material)
					return true;
		if(ignore.meshes !is null)
			foreach(MeshID mesh; ignore.meshes)
				if(v.mesh == mesh)
					return true;
		if(ignore.combinations !is null)
			foreach(Tuple!(MaterialID, MeshID) combination; ignore.combinations)
				if(v.material == combination[0] && v.mesh == combination[1])
					return true;

		return false;
	}

	foreach(i; 0 .. maxDistance * 100)
	{
		prev = curr;
		curr += (-dir * 0.01f);

		voxelPos = ChunkPosition.realCoordToBlockPos(curr);
		ChunkPosition chunkPos;
		BlockOffset blockOffset;
		ChunkPosition.blockPosToChunkPositionAndOffset(voxelPos, chunkPos, blockOffset);

		Maybe!Voxel currentVoxel = m.voxelInteraction.get(chunkPos, blockOffset);

		if(currentVoxel.isNull)
			continue;
		if(!isIgnore(*currentVoxel.unwrap))
			break;
	}

	Maybe!Voxel voxel = m.voxelInteraction.get(voxelPos);
	if(voxel.isNull)
		return PickResult(false);

	PickResult result;
	result.got = true;
	result.realPosition = curr;
	result.blockPosition = voxelPos;
	result.voxel = *voxel.unwrap;

	BlockPosition voxelPrevious = ChunkPosition.realCoordToBlockPos(prev);
	if(voxelPrevious.x > voxelPos.x) result.side = VoxelSide.px;
	else if(voxelPrevious.x < voxelPos.x) result.side = VoxelSide.nx;
	else if(voxelPrevious.y > voxelPos.y) result.side = VoxelSide.py;
	else if(voxelPrevious.y < voxelPos.y) result.side = VoxelSide.ny;
	else if(voxelPrevious.z > voxelPos.z) result.side = VoxelSide.pz;
	else if(voxelPrevious.z < voxelPos.z) result.side = VoxelSide.nz;

	return result;
}