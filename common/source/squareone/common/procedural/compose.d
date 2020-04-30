module squareone.common.procedural.compose;

import std.math;

/++
+ Provides octaves for simplex noise.
+ Params:
+	src = noise source
+	x = x coord
+	y = y coord
+	frequency = start frequency, frequency *= multiplier with every octave
+	numOctaves = number of octaves
+	multiplier = for each octave, multiple height and freq by this value
+/
float multiNoise(float delegate(float, float) src, float x, float y, float frequency, int numOctaves, float multiplier = 0.5f)
{
	float total = 0f;
	float heightMultiplier = 1f;

	foreach(octave; 0 .. numOctaves)
	{
		total += heightMultiplier * src(x / frequency, y / frequency); // for swamp, x * freq
		heightMultiplier *= multiplier;
		frequency *= multiplier; // for swamp, /= mul
	}

	return total;
}

/++
+ Provides octaves for simplex noise.
+ Params:
+	src = noise source
+	x = x coord
+	y = y coord
+	z = z coord
+	frequency = start frequency, frequency *= multiplier with every octave
+	numOctaves = number of octaves
+	multiplier = for each octave, multiple height and freq by this value
+/
float multiNoise(float delegate(float, float, float) src, float x, float y, float z, float frequency, int numOctaves, float multiplier = 0.5f)
{
	float total = 0f;
	float heightMultiplier = 1f;

	foreach(octave; 0 .. numOctaves)
	{
		total += heightMultiplier * src(x / frequency, y / frequency, z / frequency); // for swamp, x * freq
		heightMultiplier *= multiplier;
		frequency *= multiplier; // for swamp, /= mul
	}

	return total;
}

float island(float n, float distance)
{
	return (1 + n - distance) / 2;
}

float redistributeNoise(float n, float power)
{
	return pow(n, power);
}

float terrace(float val, float n, float power)
{
	float dval = val * n;
	float i = floor(dval);
	float f = dval - i;
	return (i + pow(f, power)) / n;
}