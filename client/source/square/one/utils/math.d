module square.one.utils.math;

/// Flattens a 3D coord to a 1D index.
pragma(inline, true)
int flattenIndex(int x, int y, int z, int dimensions) {
	return x + dimensions * (y + dimensions * z);
}