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

Vector2f voronoi2nd(Vector2f coord, float delegate(float x, float y) src)
{
	Vector2f baseCell = Vector2f(floor(coord.x), floor(coord.y));

	float minDistToCell = 10f, minDistToCell2 = 10f;
	Vector2f closestCell, secondClosestCell;

	float eval(Vector2f c)
	{
		return src(c.x, c.y) * 0.5f + 0.5f;
	}

	Vector2f eval2(Vector2f c)
	{
		return Vector2f(eval(c), eval(c.yx));
	}

	float[9] dists;
	Vector2f[9] poses;
	size_t i;

	foreach(x; -1 .. 2)
	{
		foreach(y; -1 .. 2)
		{
			Vector2f cell = baseCell + Vector2f(x, y);
			Vector2f cellPosition = cell + eval2(cell);
			Vector2f toCell = cellPosition - coord;
			float distToCell = toCell.length;
			/+if(distToCell < minDistToCell)
			{
				minDistToCell2 = minDistToCell;
				minDistToCell = distToCell;
				secondClosestCell = closestCell;
				closestCell = cell;
			}+/

			dists[i] = distToCell;
			poses[i] = cell;
			i++;
		}
	}

	minDistToCell2 = dists[0];
	minDistToCell = dists[0];

	foreach(x; 0 .. i)
	{
		if(dists[x] < minDistToCell)
		{
			minDistToCell2 = minDistToCell;
			minDistToCell = dists[x];
		}
		else if(dists[x] < minDistToCell2 && dists[x] != minDistToCell)
			minDistToCell2 = dists[x];
	}

	float r = eval(secondClosestCell);
	return Vector2f(minDistToCell2, r);
}