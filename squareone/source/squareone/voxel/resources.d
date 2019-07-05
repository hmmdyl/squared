module squareone.voxel.resources;

import squareone.voxel.chunk;
import squareone.voxel.voxel;
import moxane.graphics.renderer;
import moxane.core.eventwaiter;

enum string dylanGrahamName = "Dylan Graham";

interface IVoxelContent {
	/// The name the engine references this content by.
	@property string technical();
	/// The name the engine displays to the user.
	@property string display();
	/// The mod that this content is a part of.
	@property string mod();
	@property string author();
}

template VoxelContentQuick(string technical, string display, string mod, string author) {
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

interface IProcessor : IVoxelContent {
	@property ubyte id();
	@property void id(ubyte newID);

	void finaliseResources(Resources res);

	void meshChunk(MeshOrder c);
	void removeChunk(IMeshableVoxelBuffer c);

	void updateFromManager();

	/*void prepareRenderShadow(Renderer);
	void renderShadow(Chunk chunk, ref LocalContext lc);
	void endRenderShadow();*/

	void prepareRender(Renderer);
	void render(IMeshableVoxelBuffer chunk, ref LocalContext lc, ref uint drawCalls, ref uint numVerts);
	void endRender();
}

interface IVoxelMaterial : IVoxelContent {
	@property ushort id();
	@property void id(ushort newID);
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
	@property ushort id();
	@property void id(ushort newID);

	SideSolidTable isSideSolid(Voxel voxel, VoxelSide side);
}

class Resources {
	enum int maxProcessors = 256;
	enum int maxMaterials = 4096;
	enum int maxMeshes = 4096;

	private IProcessor[] processors;
	private IVoxelMaterial[] materials;
	private IVoxelMesh[] meshes;

	private IProcessor[string] procName;
	private IVoxelMaterial[string] matName;
	private IVoxelMesh[string] meshName;

	ubyte processorCount;
	ushort materialCount;
	ushort meshCount;

	package bool acceptAdditions = true;

	this() {
		processors.length = maxProcessors;
		materials.length = maxMaterials;
		meshes.length = maxMeshes;
	}

	void add(IProcessor proc) {
		if(processorCount + 1 >= maxProcessors) throw new Exception("Cannot add another processor!");
		if(!acceptAdditions) throw new Exception("Cannot accept more additions.");

		proc.id = processorCount;
		processors[processorCount] = proc;
		processorCount++;

		procName[proc.technical] = proc;
	}

	void add(IVoxelMaterial mat) {
		if(materialCount + 1 >= maxMeshes) throw new Exception("Cannot add another material!");
		if(!acceptAdditions) throw new Exception("Cannot accept more additions.");

		mat.id = materialCount;
		materials[materialCount] = mat;
		materialCount++;

		matName[mat.technical] = mat;
	}

	void add(IVoxelMesh mesh) {
		if(meshCount + 1 >= maxMeshes) throw new Exception("Cannot add another mesh!");
		if(!acceptAdditions) throw new Exception("Cannot accept more additions.");

		mesh.id = meshCount;
		meshes[meshCount] = mesh;
		meshCount++;

		meshName[mesh.technical] = mesh;
	}

	void finaliseResources() {
		acceptAdditions = false;

		foreach(IProcessor processor; processors) {
			if(processor is null) continue;
			processor.finaliseResources(this);
		}
	}

	IVoxelMesh getMesh(int i) { return meshes[i]; }
	IVoxelMesh getMesh(string i) { return meshName[i]; }
	IVoxelMaterial getMaterial(int i) { return materials[i]; }
	IVoxelMaterial getMaterial(string i) { return matName[i]; }
	IProcessor getProcessor(int i) { return processors[i]; }
}