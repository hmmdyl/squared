module squareone.entities.components.head;

import moxane.core;
public import moxane.graphics.transformation;

@safe:

struct HeadTransform
{
	Transform transform;
	alias transform this;

	this(Transform transform) { this.transform = transform; }
}