module squareone.util.voronoi;

import squareone.terrain.gen.simplex;

import dlib.math;
import std.math;

Matrix2f myt = Matrix2f([.12121212f, .13131313f, -.13131313f, .12121212f]);
Vector2f mys = Vector2f(1e4, 1e6);

float fract(float x)
{
	return x - floor(x);
}

Vector2f fract2(Vector2f x)
{
	return Vector2f(fract(x.x), fract(x.y));
}

Vector2f rhash(Vector2f uv)
{
	uv = uv * myt;
	uv *= mys;
	return fract2(fract2(uv / mys) * uv);
}

float voronoi2D(Vector2f coord)
{

	Vector2f p = Vector2f(floor(coord.x), floor(coord.y));
	Vector2f f = Vector2f(fract(coord.x), fract(coord.y));
	float res = 0f;

	foreach(x; -1 .. 2)
	{
		foreach(y; -1 .. 2)
		{
			Vector2f b = Vector2f(x, y);
			Vector2f r = b - f + rhash(p + b);
			res += 1f / pow(dot(r, r), 8);
		}
	}
	return pow(1 / res, 0.0625);
}

float r2dTo1d(Vector2f v, Vector2f d = Vector2f(12.9898f, 78.233f))
{
	Vector2f sm = Vector2f(sin(v.x), sin(v.y));
	float r = dot(sm, d);
	r = sin(r) * 143758.5453f;
	r = r - floor(r);
	return r;
}

Vector2f r2dTo2d(Vector2f v)
{
	return Vector2f(
					r2dTo1d(v, Vector2f(12.989f, 78.233f)),
					r2dTo1d(v, Vector2f(39.346f, 11.135f)));
}

Vector2f voronoi(Vector2f coord, OpenSimplexNoise!float osn)
{
	Vector2f baseCell = Vector2f(floor(coord.x), floor(coord.y));

	float minDistToCell = 10f;
	Vector2f closestCell;

	float simplexEval(Vector2f c)
	{
		return osn.eval(c.x, c.y) * 0.5f + 0.5f;
	}

	Vector2f simplexEval2(Vector2f c)
	{
		return Vector2f(simplexEval(c), simplexEval(c.yx));
	}

	foreach(x; -1 .. 2)
	{
		foreach(y; -1 .. 2)
		{
			Vector2f cell = baseCell + Vector2f(x, y);
			//Vector2f cellPosition = cell + r2dTo2d(cell);
			Vector2f cellPosition = cell + simplexEval2(cell);
			Vector2f toCell = cellPosition - coord;
			float distToCell = toCell.length;
			if(distToCell < minDistToCell)
			{
				minDistToCell = distToCell;
				closestCell = cell;
			}
		}
	}

	float r = simplexEval(closestCell);
	return Vector2f(minDistToCell, r);
}