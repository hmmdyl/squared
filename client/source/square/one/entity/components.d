module square.one.entity.components;

import entitysysd;

import gfm.math;

@component struct TransformComponent {
	vec3d position;
	vec3f rotation;
}

@component struct PhysicsComponent {
	vec3d acceleration;
}

@component struct RigidBodyComponent {

}

@component struct ScriptComponent {
	package bool started;

	Object tag;

	void delegate(ref Entity entity) onStart;
	void delegate(ref Entity entity) onExecute;
}

@component struct AsyncScriptComponent {
	package bool started;

	import core.thread : Fiber;
	Fiber fiber;

	void delegate(ref Entity entity) onStart;

	void setDelegate(void delegate(ref Entity entity) onStartDel, ref Entity entity) {
		onStart = onStartDel;
		fiber = new Fiber(() => onStart(entity));
	}
}