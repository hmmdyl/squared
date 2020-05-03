module squareone.common.terrain.basic.packets;

import squareone.common.voxel;

import moxane.network;

import std.stdio : writeln;
import std.traits;

@safe:

align(1) struct VoxelUpdate
{
	static string technicalName() { return typeid(VoxelUpdate).name; }

	PacketID packetID;

	Voxel updated, previous;
	int x, y, z;
}

template GetPackets(alias mn)
{
	string[] packets()
	{
		string[] result;
		static foreach(memberName; __traits(allMembers, mn))
		{{
			alias candidate = __traits(getMember, mn, memberName);

			static if(is(candidate == struct))
			{
				static if(__traits(compiles, candidate.technicalName))
				{
					result ~= moduleName!mn ~ "." ~ candidate.stringof;
				}
				else static assert(0);
			}
		}}

		return result;
	}

	enum string[] GetPackets = packets();
}