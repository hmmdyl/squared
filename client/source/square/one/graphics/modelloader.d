module square.one.graphics.modelloader;

import derelict.assimp3.assimp;

import std.string;
import gfm.math.vector;

void loadModelVerts(string file, out vec3f[] vertices) {
	const(aiScene*) scene = aiImportFile(toStringz(file), aiProcess_Triangulate);
	if(scene == null)
		throw new Exception("Could not load model from file \"" ~ file ~ "\".");
	
	foreach(uint i; 0 .. scene.mNumMeshes) {
		const(aiMesh)* mesh = scene.mMeshes[i];
		int nmeshfaces = mesh.mNumFaces;
		foreach(uint j; 0 .. nmeshfaces) {
			const(aiFace) face = mesh.mFaces[j];
			foreach(uint k; 0 .. 3) {
				aiVector3D vert = mesh.mVertices[face.mIndices[k]];
				
				vertices ~= vec3f(vert.x, vert.y, vert.z);
			}
		}
	}
}

void loadModelVertsNorms(string file, out vec3f[] vertices, out vec3f[] normals) {
	const(aiScene*) scene = aiImportFile(toStringz(file), aiProcess_Triangulate);
	if(scene == null)
		throw new Exception("Could not load model from file \"" ~ file ~ "\".");

	foreach(uint i; 0 .. scene.mNumMeshes) {
		const(aiMesh)* mesh = scene.mMeshes[i];
		int nmeshfaces = mesh.mNumFaces;
		foreach(uint j; 0 .. nmeshfaces) {
			const(aiFace) face = mesh.mFaces[j];
			foreach(uint k; 0 .. 3) {
				aiVector3D vert = mesh.mVertices[face.mIndices[k]];
				aiVector3D normal = mesh.mNormals[face.mIndices[k]];

				vertices ~= vec3f(vert.x, vert.y, vert.z);
				normals ~= vec3f(normal.x, normal.y, normal.z);
			}
		}
	}
}

void loadModelVertsNormsUVs(string file, out vec3f[] vertices, out vec3f[] normals, out vec2f[] uvs) {
	const(aiScene*) scene = aiImportFile(toStringz(file), aiProcess_Triangulate);
	if(scene == null)
		throw new Exception("Could not load model from file \"" ~ file ~ "\".");
	
	foreach(uint i; 0 .. scene.mNumMeshes) {
		const(aiMesh)* mesh = scene.mMeshes[i];
		int nmeshfaces = mesh.mNumFaces;
		foreach(uint j; 0 .. nmeshfaces) {
			const(aiFace) face = mesh.mFaces[j];
			foreach(uint k; 0 .. 3) {
				aiVector3D vert = mesh.mVertices[face.mIndices[k]];
				aiVector3D normal = mesh.mNormals[face.mIndices[k]];
				aiVector3D uv = mesh.mTextureCoords[0][face.mIndices[k]];
				
				vertices ~= vec3f(vert.x, vert.y, vert.z);
				normals ~= vec3f(normal.x, normal.y, normal.z);
				uvs ~= vec2f(uv.x, uv.y);
			}
		}
	}
}