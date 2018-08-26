module square.one.terrain.edittool;

import gfm.math;
import std.math;

import square.one.terrain.resources;
import square.one.terrain.manager;
import square.one.terrain.chunk;

class EditTool {
	void update(vec3f pos, vec3f rot, TerrainManager man, bool breakDown, bool placeDown, out vec3l de, out vec3f realPos, out vec3i n) {
		vec3f origRot = rot;

		rot.x = radians(rot.x);
		rot.y = radians(rot.y);
		rot.z = radians(rot.z);

		vec3f dir;
		dir.x = sin(-rot.y) * cos(-rot.x);
		dir.y = sin(rot.x);
		dir.z = cos(-rot.y) * cos(-rot.x);

		vec3f previousPos = pos;
		vec3f position = pos;

		vec3l rayc;

		foreach(int i; 0 .. 200) { // 20 metres
			previousPos = position;
			position += (-dir * 0.1f);

			vec3l blockPos = ChunkPosition.realCoordToBlockPos(position);
			rayc = blockPos;

			bool got;
			Voxel vox = man.getVoxel(blockPos, got);

			if(got)
				if(vox.material != 0)
					break;
		}

		//de = rayc;
		realPos = position;

		bool got;
		Voxel vox = man.getVoxel(rayc, got);
		if(!got) {
			return;
		}
		if(vox.material == 0)
			return;

		vec3l p = ChunkPosition.realCoordToBlockPos(previousPos);

		vec3i face;
		if(p.x > rayc.x) face.x = 1;
		else if(p.x < rayc.x) face.x = -1;
		else if(p.y > rayc.y) face.y = 1;
		else if(p.y < rayc.y) face.y = -1;
		else if(p.z > rayc.z) face.z = 1;
		else if(p.z < rayc.z) face.z = -1;

		n = face;
		de = rayc;

		if(breakDown) {
			SetBlockCommand comm;
			comm.bx = rayc.x;
			comm.by = rayc.y;
			comm.bz = rayc.z;
			comm.over = Voxel(0, 0, 0, 0);

			foreach(int ex; 0 .. 1) {
				foreach(int ey; 0 .. 1) {
					foreach(int ez; 0 .. 1) {
						comm.bx = rayc.x + ex;
						comm.by = rayc.y + ey;
						comm.bz = rayc.z + ez;
						man.addSetBlockCommand(comm);
					}
				}
			}

			//man.addSetBlockCommand(comm);
		}

		if(placeDown) {
			if(face.x == -1) rayc.x -= 1;
			if(face.x == 1) rayc.x += 1;
			if(face.y == -1) rayc.y -= 1;
			if(face.y == 1) rayc.y += 1;
			if(face.z == -1) rayc.z -= 1;
			if(face.z == 1) rayc.z += 1;

			SetBlockCommand comm;
			comm.bx = rayc.x;
			comm.by = rayc.y;
			comm.bz = rayc.z;
			comm.over = Voxel(1, 1, 0, 0);
			man.addSetBlockCommand(comm);
		}
	}
}