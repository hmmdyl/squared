module squareone.common.meta;

import std.typecons;

enum name = "Square One";
enum engine = "Moxane";

enum currentVersion = tuple(0, 0, 2);
enum currentVersionStr = "v" ~ to!string(currentVersion[0]) ~ "." ~ 
	to!string(currentVersion[1]) ~ "." ~ 
	to!string(currentVersion[2]);

enum dylanGraham = "Dylan Josh Graham";