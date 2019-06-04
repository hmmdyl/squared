module squareone.util.spec;

import std.typecons : Tuple;

enum string appName = "SquareOne";

enum Tuple!(int, int, int) gameVersion = Tuple!(int, int, int)(0, 0, 2);

string resourceName(string item, string area, string mod = appName) pure @safe
{ return mod ~ ":" ~ area ~ ":" ~ item; }