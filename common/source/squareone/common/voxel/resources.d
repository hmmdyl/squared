module squareone.common.voxel.resources;

import squareone.common.voxel.chunk;
import squareone.common.voxel.voxel;

import moxane.core;

@safe:

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

interface IWorkerThread(T)
{
	@property IChannel!T source();

	float averageMeshTime();

	@property bool parked() const;
	@property bool terminated() const;
	void kick();
	void terminate();
}

interface IMesher : IWorkerThread!MeshOrder {}

interface IVoxelMaterial : IVoxelContent {
	@property MaterialID id();
	@property void id(MaterialID newID);
}

enum SideSolidTable : ubyte {
	notSolid = 0,
	solid,
	slope_0_1_3,
	slope_1_3_2,
	slope_0_2_3,
	slope_2_0_1
}

interface IVoxelMesh : IVoxelContent {
	@property MeshID id();
	@property void id(MeshID newID);

	SideSolidTable isSideSolid(Voxel voxel, VoxelSide side);
}

enum meshBitLength = 12;
enum meshBits = 0xFFF;

interface IProcessor : IVoxelContent
{
	@property ProcID id() const;
	@property void id(ProcID);

	void finaliseResources();

	void removeChunk(IMeshableVoxelBuffer c);

	void updateFromManager();

	@property size_t minMeshers() const;
	IMesher requestMesher(IChannel!MeshOrder);
	void returnMesher(IMesher);
}

class VoxelRegistry
{
	enum maxProcessors = 256;
	enum maxMaterials = 4096;
	enum maxMeshes = 4096;

	private IProcessor[] processors;
	private IVoxelMaterial[] materials;
	private IVoxelMesh[] meshes;

	private IProcessor[string] procName;
	private IVoxelMaterial[string] matName;
	private IVoxelMesh[string] meshName;

	@property ProcID processorCount() const { return cast(ProcID)processors.length; }
	@property MaterialID materialCount() const { return cast(MaterialID)materials.length; }
	@property MeshID meshCount() const { return cast(MeshID)meshes.length; }

	package bool acceptingAdditions = true;

	this()
	{
		processors = new IProcessor[](0);
		materials = new IVoxelMaterial[](0);
		meshes = new IVoxelMesh[](0);
	}

	void add(IProcessor proc) {
		if(processorCount + 1 >= maxProcessors) throw new Exception("Cannot add another processor!");
		if(!acceptingAdditions) throw new Exception("Cannot accept more additions.");

		proc.id = processorCount;
		processors ~= proc;

		procName[proc.technical] = proc;
	}

	void add(IVoxelMaterial mat) {
		if(materialCount + 1 >= maxMeshes) throw new Exception("Cannot add another material!");
		if(!acceptingAdditions) throw new Exception("Cannot accept more additions.");

		mat.id = materialCount;
		materials ~= mat;

		matName[mat.technical] = mat;
	}

	void add(IVoxelMesh mesh) {
		if(meshCount + 1 >= maxMeshes) throw new Exception("Cannot add another mesh!");
		if(!acceptingAdditions) throw new Exception("Cannot accept more additions.");

		mesh.id = meshCount;
		meshes ~= mesh;

		meshName[mesh.technical] = mesh;
	}

	void finaliseResources() @trusted {
		acceptingAdditions = false;
		meshName.rehash;
		matName.rehash;
		procName.rehash;

		foreach(IProcessor processor; processors) {
			if(processor is null) continue;
			processor.finaliseResources();
		}
	}

	IVoxelMesh getMesh(int i) { return meshes[i]; }
	IVoxelMesh getMesh(string i) { return meshName[i]; }
	IVoxelMaterial getMaterial(int i) { return materials[i]; }
	IVoxelMaterial getMaterial(string i) { return matName[i]; }
	IProcessor getProcessor(int i) { return processors[i]; }
}