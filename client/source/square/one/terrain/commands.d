module square.one.terrain.commands;

import square.one.terrain.voxel;

struct SetBlockCommand {
    long x, y, z;
    Voxel set;
}