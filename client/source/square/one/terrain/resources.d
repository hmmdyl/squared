module square.one.terrain.resources;

public import square.one.terrain.chunk;
public import square.one.terrain.voxel;

public import moxana.graphics.rendercontext;

enum string squareOneMod = "mod_square_one_default";
enum string dylanGrahamName = "Dylan Graham (djg_0)";

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

interface IProcessor : IVoxelContent {
	@property ubyte id();
	@property void id(ubyte newID);

	void finaliseResources(Resources res);

	void meshChunk(IMeshableVoxelBuffer c);
	void removeChunk(IMeshableVoxelBuffer c);

	void updateFromManager();

	void prepareRenderShadow(RenderContext context);
	void renderShadow(Chunk chunk, ref LocalRenderContext lrc);
	void endRenderShadow();

	void prepareRender(RenderContext camera);
	void render(Chunk chunk, ref LocalRenderContext lrc);
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
	public enum int maxProcessors = 256;
	public enum int maxMaterials = 4096;
	public enum int maxMeshes = 4096;

	private IProcessor[] processors;
	private IVoxelMaterial[] materials;
	private IVoxelMesh[] meshes;

	private IProcessor[string] procName;
	private IVoxelMaterial[string] matName;
	private IVoxelMesh[string] meshName;

	public ubyte processorCount;
	public ushort materialCount;
	public ushort meshCount;

	package bool acceptAdditions = true;

	public this() {
		processors.length = maxProcessors;
		materials.length = maxMaterials;
		meshes.length = maxMeshes;
	}

	public void add(IProcessor proc) {
		if(processorCount + 1 >= maxProcessors) throw new Exception("Cannot add another processor!");
		if(!acceptAdditions) throw new Exception("Cannot accept more additions.");

		proc.id = processorCount;
		processors[processorCount] = proc;
		processorCount++;

		procName[proc.technical] = proc;
	}

	public void add(IVoxelMaterial mat) {
		if(materialCount + 1 >= maxMeshes) throw new Exception("Cannot add another material!");
		if(!acceptAdditions) throw new Exception("Cannot accept more additions.");

		mat.id = materialCount;
		materials[materialCount] = mat;
		materialCount++;

		matName[mat.technical] = mat;
	}

	public void add(IVoxelMesh mesh) {
		if(meshCount + 1 >= maxMeshes) throw new Exception("Cannot add another mesh!");
		if(!acceptAdditions) throw new Exception("Cannot accept more additions.");

		mesh.id = meshCount;
		meshes[meshCount] = mesh;
		meshCount++;

		meshName[mesh.technical] = mesh;
	}

	public void finaliseResources() {
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