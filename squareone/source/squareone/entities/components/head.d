module squareone.entities.components.head;

import moxane.core;

import dlib.math.vector;

@safe:

/// This represents the transform of a head. Must be coupled with a Transform
struct HeadTransform
{
	Vector3f offset;
	Vector3f rotation;

	/// how long the head can rotate until it starts moving the body
	float yRotBodyTurnThreshold;
}