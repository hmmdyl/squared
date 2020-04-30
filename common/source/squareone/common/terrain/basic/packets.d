module squareone.common.terrain.basic.packets;

import squareone.common.voxel;

import moxane.network;

@safe:

struct VoxelUpdate
{
	static string technicalName() { return typeid(VoxelUpdate).name; };

	PacketID packetID;

	Voxel updated, previous;
	BlockPosition pos;
}