module squareone.util.procgen.voronoi;

import squareone.util.procgen.simplex;

import dlib.math;
import std.math;

Vector2f voronoi(Vector2f coord, float delegate(float x, float y) src)
{
	Vector2f baseCell = Vector2f(floor(coord.x), floor(coord.y));

	float minDistToCell = 10f;
	Vector2f closestCell;

	float eval(Vector2f c)
	{
		return src(c.x, c.y) * 0.5f + 0.5f;
	}

	Vector2f eval2(Vector2f c)
	{
		return Vector2f(eval(c), eval(c.yx));
	}

	foreach(x; -1 .. 2)
	{
		foreach(y; -1 .. 2)
		{
			Vector2f cell = baseCell + Vector2f(x, y);
			Vector2f cellPosition = cell + eval2(cell);
			Vector2f toCell = cellPosition - coord;
			float distToCell = toCell.length;
			if(distToCell < minDistToCell)
			{
				minDistToCell = distToCell;
				closestCell = cell;
			}
		}
	}

	float r = eval(closestCell);
	return Vector2f(minDistToCell, r);
}