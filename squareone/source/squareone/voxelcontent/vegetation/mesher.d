module squareone.voxelcontent.vegetation.mesher;

import squareone.voxel;
import squareone.voxelcontent.vegetation.processor;
import squareone.voxelcontent.vegetation.types;
import squareone.voxelcontent.vegetation.precalc;

import moxane.core;
import moxane.utils.maybe;

import dlib.math;

import std.concurrency;
import core.atomic;

package final class Mesher : IMesher
{
	private IChannel!MeshOrder source_;
	@property IChannel!MeshOrder source() { return source_; }

	private shared float averageMeshTime_ = 0f;
	@property float averageMeshTime() { return atomicLoad(averageMeshTime_); }

	private shared bool parked_ = true, terminated_ = false;
	@property bool parked() const { return atomicLoad(parked_); }
	private @property void parked(bool n) { atomicStore(parked_, n); }
	@property bool terminated() const { return atomicLoad(terminated_); }
	private @property void terminated(bool n) { atomicStore(terminated_, n); }

	private Tid thread;

	VegetationProcessor processor;

	this(VegetationProcessor processor, IChannel!MeshOrder source)
	in(processor !is null) in(source !is null)
	{
		this.source_ = source;
		this.processor = processor;

		thread = spawn(&worker, cast(shared)this, cast(shared)processor); 
	}

	void kick() { send(thread, true); }
	void terminate() { send(thread, false); }
}

private void worker(shared Mesher mesherS, shared VegetationProcessor processorS)
in(mesherS !is null) in(processorS !is null)
{
	Mesher mesher = cast(Mesher)mesherS;
	VegetationProcessor processor = cast(VegetationProcessor)processorS;

	scope(failure)
	{
		auto log = processor.moxane.services.getAOrB!(VoxelLog, Log);
		enum threadName = VegetationProcessor.stringof ~ Mesher.stringof;
		log.write(Log.Severity.panic, "Panic in " ~ threadName);
	}

	while(!mesher.terminated)
	{
		receive(
			(bool m)
			{
				if(!m)
				{
					mesher.terminated = false;
					return;
				}

				mesher.parked = false;
				scope(exit) mesher.parked = true;

				bool consuming = true;
				while(consuming)
				{
					Maybe!MeshOrder order = mesher.source_.tryGet;
					if(order.isNull) consuming = false;
					else
						operate(*order.unwrap, mesher);
				}
			}
		);
	}
}

private void operate(MeshOrder order, Mesher mesher)
{
	VegetationProcessor processor = mesher.processor;

	MeshBuffer buffer;
	do buffer = processor.meshBufferPool.get;
	while(buffer is null);

	immutable int blockskip = order.chunk.blockskip;
	immutable int chunkDimLod = order.chunk.dimensionsProper * order.chunk.blockskip;

	for(int x = 0; x < chunkDimLod; x += blockskip)
	for(int y = 0; y < chunkDimLod; y += blockskip)
	for(int z = 0; z < chunkDimLod; z += blockskip)
	{
		Voxel voxel = order.chunk.get(x, y, z);

		IVegetationVoxelMesh* meshPtr = voxel.mesh in processor.meshes;
		if(meshPtr is null) continue;
		IVegetationVoxelMesh mesh = *meshPtr;

		Voxel ny = order.chunk.get(x, y - blockskip, z);
		const bool shiftDown = mesher.processor.resources.getMesh(ny.mesh).isSideSolid(ny, VoxelSide.py) != SideSolidTable.solid;

		const Vector3f colour = voxel.extractColour;
		ubyte[4] colourBytes = [
			cast(ubyte)(colour.x * 255),
			cast(ubyte)(colour.y * 255),
			cast(ubyte)(colour.z * 255),
			0
		];

		IVegetationVoxelMaterial* materialPtr = voxel.material in processor.materials;
		if(materialPtr is null) throw new Exception("Yeetus");
		IVegetationVoxelMaterial material = *materialPtr;

		if(mesh.meshType == MeshType.grass)
		{
			GrassVoxel gv = GrassVoxel(voxel);
			float height = gv.blockHeight;
			colourBytes[3] = material.grassTexture;

			Matrix4f rotMat = rotationMatrix(Axis.y, degtorad((360f / 8f) * gv.offset)) * translationMatrix(Vector3f(-0.5f, -0.5f, -0.5f));
			Matrix4f retTraMat = translationMatrix(Vector3f(0.5f, 0.5f, 0.5f));

			foreach(size_t vid, immutable Vector3f v; grassBundle2)
			{
				size_t tid = vid % grassPlane.length;
				Vector2f texCoord = Vector2f(grassPlaneTexCoords[tid]);
				Vector3f vertex = ((Vector4f(v.x, v.y, v.z, 1f) * rotMat) * retTraMat).xyz;

				import std.math;
				ubyte offset = gv.offset;
				float xOffset = offset == 0 ? 0f : cos(degtorad((360f / 7f) * (offset-1))) * 0.25f;
				float yOffset = offset == 0 ? 0f : sin(degtorad((360f / 7f) * (offset-1))) * 0.25f;

				vertex += Vector3f(xOffset, 0f, yOffset);

				vertex = (vertex * Vector3f(1f, height + (height * gv.heightOffset), 1f)) * order.chunk.blockskip + Vector3f(x, y, z);
				if(shiftDown) vertex.y -= order.chunk.blockskip;
				vertex *= order.chunk.voxelScale;
				buffer.add(vertex, colourBytes, texCoord);
			}
		}
		else if(mesh.meshType == MeshType.leaf)
		{
			LeafVoxel lv = LeafVoxel(voxel);

			float rotation;
			final switch(lv.direction) with(LeafVoxel.Direction)
			{
				case negative90:
					rotation = -45f;
					break;
				case negative45:
					rotation = 0f;
					break;
				case zero:
					rotation = 45f;
					break;
				case positive45:
					rotation = 90f;
					break;
			}

			Matrix4f rotMat =
				rotationMatrix(Axis.y, degtorad(lv.rotation * (360f / 8f))) *
				rotationMatrix(Axis.x, degtorad(rotation)) *
				translationMatrix(Vector3f(-0.5f, -0.5f, -0.5f));
			Matrix4f retTraMat = translationMatrix(Vector3f(0.5f, 0.5f, 0.5f));

			foreach(size_t vid, immutable Vector3f v; leafPlane)
			{
				size_t texCoordID = vid % leafPlaneTexCoords.length;
				Vector2f texCoord = Vector2f(leafPlaneTexCoords[texCoordID]);
				Vector3f vertex = ((Vector4f(v.x, v.y, v.z, 1f) * rotMat) * retTraMat).xyz;

				vertex = vertex * order.chunk.blockskip + Vector3f(x, y, z);
				vertex *= order.chunk.voxelScale;

				buffer.add(vertex, colourBytes, texCoord);
			}
		}
	}

	if(buffer.vertexCount == 0)
	{
		buffer.reset;
		processor.meshBufferPool.give(buffer);
		buffer = null;

		MeshResult mr;
		mr.order = order;
		mr.buffer = null;
		processor.meshResults.send(mr);
	}
	else
	{
		MeshResult mr;
		mr.order = order;
		mr.buffer = buffer;
		processor.meshResults.send(mr);
	}
}

struct MeshResult
{
	MeshOrder order;
	MeshBuffer buffer;
}

package enum bufferMaxVertices = 2 ^^ 14;

package final class MeshBuffer
{
	Vector3f[] vertices;
	ubyte[] colours;
	Vector2f[] texCoords;
	ushort vertexCount;

	this()
	{
		vertices.length = bufferMaxVertices;
		colours.length = bufferMaxVertices * 4;
		texCoords.length = bufferMaxVertices;
	}

	void reset() { vertexCount = 0; }

	void add(Vector3f vertex, ubyte[4] colour, Vector2f texCoord)
	{
		vertices[vertexCount] = vertex;
		colours[vertexCount * 4 .. vertexCount * 4 + 4] = colour[];
		texCoords[vertexCount] = texCoord;
		vertexCount++;
	}
}