module squareone.content.voxel.vegetation.precalc;

import dlib.math;

// ------------------------- START GRASS -------------------------
 
package __gshared static Vector3f[] grassBundle3;
package __gshared static Vector3f[] grassBundle2;

package immutable Vector3f[] grassPlane = [
	Vector3f(0, 0, 0.5),
	Vector3f(1, 0, 0.5),
	Vector3f(1, 1, 0.5),  
	Vector3f(1, 1, 0.5),
	Vector3f(0, 1, 0.5),
	Vector3f(0, 0, 0.5)
];

package immutable Vector3f[] grassPlaneSlanted = [
	Vector3f(-0.5, 0, 0.35),
	Vector3f(1.5, 0, 0.35),
	Vector3f(1.5, 1, 0.9),  
	Vector3f(1.5, 1, 0.9),
	Vector3f(-0.5, 1, 0.9),
	Vector3f(-0.5, 0, 0.35)
];

package Vector3f[] calculateGrassBundle(immutable Vector3f[] grassSinglePlane, uint numPlanes)
in(numPlanes > 0 && numPlanes <= 10)
do {
	Vector3f[] result = new Vector3f[](grassSinglePlane.length * numPlanes);
	size_t resultI;

	const float segment = 180f / numPlanes;
	foreach(planeNum; 0 .. numPlanes)
	{
		float rotation = segment * planeNum;
		Matrix4f rotMat = rotationMatrix(Axis.y, degtorad(rotation)) * translationMatrix(Vector3f(-0.5f, -0.5f, -0.5f));

		foreach(size_t vid, immutable Vector3f v; grassSinglePlane)
		{
			Vector3f vT = ((Vector4f(v.x, v.y, v.z, 1f) * rotMat) * translationMatrix(Vector3f(0.5f, 0.5f, 0.5f))).xyz;
			result[resultI++] = vT;
		}
	}

	return result;
}

package immutable Vector2f[] grassPlaneTexCoords = [
	/+Vector2f(0.25, 0),
	Vector2f(0.75, 0),
	Vector2f(0.75, 1),
	Vector2f(0.75, 1),
	Vector2f(0.25, 1),
	Vector2f(0.25, 0),+/
	Vector2f(0, 0),
	Vector2f(1, 0),
	Vector2f(1, 1),
	Vector2f(1, 1),
	Vector2f(0, 1),
	Vector2f(0, 0),
	];
// ------------------------- END GRASS -------------------------

package immutable Vector3f[] leafPlane = 
[
	Vector3f(0, 0, 0.0),
	Vector3f(1, 0, 0.0),
	Vector3f(1, 1, 1.0),  
	Vector3f(1, 1, 1.0),
	Vector3f(0, 1, 1.0),
	Vector3f(0, 0, 0.0)
];
package immutable Vector2f[] leafPlaneTexCoords = grassPlaneTexCoords.idup;

shared static this() 
{ 
	grassBundle3 = calculateGrassBundle(grassPlane, 3);
	grassBundle2 = calculateGrassBundle(grassPlaneSlanted, 2);
}