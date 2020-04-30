module squareone.common.terrain.basic.picker;

import squareone.common.voxel;
import squareone.common.terrain.basic.interaction;
import squareone.common.terrain.position;

import dlib.math;
import std.math : sin, cos, fmod, floor;
import std.typecons : Tuple, tuple;

import moxane.utils.maybe : Maybe;

@safe:

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

PickResult pick(Vector3f origin, Vector3f originRot, IVoxelInteraction m, 
				const int maxDistance, const PickerIgnore ignore)
{
	float modCust(float value, float modulus) { return fmod((fmod(value, modulus) + modulus), modulus);}
	int signNum(float x) { return x > 0 ? 1 : x < 0 ? -1 : 0; }
	float intBound(float s, float ds)
	{
		if(ds < 0)
		{
			s = -s;
			ds = -ds;
		}
		s = modCust(s, 1);
		return (1 - s) / ds;
	}
	bool isIgnore(immutable Voxel v)
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

	originRot.x = degtorad(originRot.x);
	originRot.y = degtorad(originRot.y);
	Vector3f rayDirection;
	rayDirection.x = sin(-originRot.y) * cos(-originRot.x);
	rayDirection.y = sin(originRot.x);
	rayDirection.z = cos(-originRot.y) * cos(-originRot.x);

	rayDirection.x = -rayDirection.x;
	rayDirection.z = -rayDirection.z;
	rayDirection.y = -rayDirection.y;

	BlockPosition blockPos = ChunkPosition.realCoordToBlockPos(origin);
	long x = blockPos.x, y = blockPos.y, z = blockPos.z;

	int stepX = signNum(rayDirection.x);
	int stepY = signNum(rayDirection.y);
	int stepZ = signNum(rayDirection.z);
	float tMaxX = intBound(origin.x * 4, rayDirection.x); // TODO EVAL IF MULTIPLIER SHOULD REMAIN
	float tMaxY = intBound(origin.y * 4, rayDirection.y);
	float tMaxZ = intBound(origin.z * 4, rayDirection.z);
	float tDeltaX = cast(float)stepX / rayDirection.x;
	float tDeltaY = cast(float)stepY / rayDirection.y;
	float tDeltaZ = cast(float)stepZ / rayDirection.z;
	Vector3i face; 
	Maybe!Voxel hit;

	auto minBounds = BlockPosition(x - maxDistance, y - maxDistance, z - maxDistance),
		maxBounds = BlockPosition(x + maxDistance, y + maxDistance, z + maxDistance);

	while((stepX > 0 ? x < maxBounds.x : x >= minBounds.x) &&
		  (stepY > 0 ? y < maxBounds.y : y >= minBounds.y) &&
		  (stepZ > 0 ? z < maxBounds.z : z >= minBounds.z))
	{
		if(x < maxBounds.x && x >= minBounds.x &&
		   y < maxBounds.y && y >= minBounds.y &&
		   z < maxBounds.z && z >= minBounds.z)
		{
			ChunkPosition chunkPos;
			BlockOffset blockOffset;
			ChunkPosition.blockPosToChunkPositionAndOffset(BlockPosition(x, y, z), chunkPos, blockOffset);
			Maybe!Voxel v = m.get(chunkPos, blockOffset);
			if(v.isNull) continue;
			if(!isIgnore(*v.unwrap))
			{
				hit = v;
				break;
			}
		}

		if(tMaxX < tMaxY) {
			if(tMaxX < tMaxZ) {
				x += stepX;
				tMaxX += tDeltaX;
				face = Vector3i(-stepX, 0, 0);
			}
			else {
				z += stepZ;
				tMaxZ += tDeltaZ;
				face = Vector3i(0, 0, -stepZ);
			}
		}
		else {
			if(tMaxY < tMaxZ) {
				y += stepY;
				tMaxY += tDeltaY;
				face = Vector3i(0, -stepY, 0);
			}
			else {
				z += stepZ;
				tMaxZ += tDeltaZ;
				face = Vector3i(0, 0, -stepZ);
			}
		}
	}

	if(hit.isNull) return PickResult(false);

	PickResult result;
	result.got = true;
	result.realPosition = Vector3f(tMaxX, tMaxY, tMaxZ);
	result.blockPosition = BlockPosition(x, y, z);
	result.voxel = *hit.unwrap;

	if(face.x > 0) result.side = VoxelSide.px;
	else if(face.x < 0) result.side = VoxelSide.nx;
	else if(face.y > 0) result.side = VoxelSide.py;
	else if(face.y < 0) result.side = VoxelSide.ny;
	else if(face.z > 0) result.side = VoxelSide.pz;
	else if(face.z < 0) result.side = VoxelSide.nz;

	return result;
}