module square.one.data;

import std.conv : to;

enum string gameName = "Square One";

enum int versionMajor = 0;
enum int versionMinor = 0;
enum int versionRevision = 1;

enum string gameVersion = to!string(versionMajor) ~ "." ~ to!string(versionMinor) ~ "." ~ to!string(versionRevision);