module squareone.util.cube;

import dlib.math.vector : Vector3f;

immutable Vector3f[8] cubeVertices = [
	Vector3f(0, 0, 0), // ind0
	Vector3f(1, 0, 0), // ind1
	Vector3f(0, 0, 1), // ind2
	Vector3f(1, 0, 1), // ind3
	Vector3f(0, 1, 0), // ind4
	Vector3f(1, 1, 0), // ind5
	Vector3f(0, 1, 1), // ind6
	Vector3f(1, 1, 1)  // ind7
];

immutable ushort[3][2][6] cubeIndices = [
	[[0, 2, 6], [6, 4, 0]], // -X
	[[7, 3, 1], [1, 5, 7]], // +X
	[[0, 1, 3], [3, 2, 0]], // -Y
	[[7, 5, 4], [4, 6, 7]], // +Y
	[[5, 1, 0], [0, 4, 5]], // -Z
	[[2, 3, 7], [7, 6, 2]]  // +Z
];

immutable Vector3f[6] cubeNormals = [
	Vector3f(-1, 0, 0),
	Vector3f(1, 0, 0),
	Vector3f(0, -1, 0),
	Vector3f(0, 1, 0),
	Vector3f(0, 0, -1),
	Vector3f(0, 0, 1)
];