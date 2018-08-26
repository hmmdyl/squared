module square.one.terrain.commands;

struct SetBlockCommand {
    long x, y, z;
    Voxel set;
}