module squareone.common.resources;

import squareone.common.voxel.chunk;

interface IVoxelContent 
{
	@property string technical(); /// The name the engine references this content by.
	@property string display(); /// The name the engine displays to the user.
	@property string mod(); /// The mod that this content is a part of.
	@property string author(); /// Author of this content
}

template VoxelContentQuick(string technical, string display, string mod, string author)
{
	const char[] VoxelContentQuick = "
		@property string technical() { return \"" ~ technical ~ "\"; }
		@property string display() { return \"" ~ display ~ "\"; }
		@property string mod() { return \"" ~ mod ~ "\"; }
		@property string author() { return \"" ~ author ~ "\"; }"; 
}

struct MeshOrder
{
	IMeshableVoxelBuffer chunk;
	bool graphics;
	bool physics;
	bool custom;
}

alias ProcID = ubyte;
alias MaterialID = ushort;
alias MeshID = ushort;