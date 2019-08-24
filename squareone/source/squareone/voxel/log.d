module squareone.voxel.log;

import moxane.core.log;

@safe:

class VoxelLog : Log
{
	this()
	{
		super("voxelLog", "Voxel");
	}
}