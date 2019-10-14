module squareone.entities.player;

import moxane.core;
import moxane.io;
import moxane.graphics.renderer;
import moxane.graphics.firstperson;
import moxane.network.semantic;
import moxane.physics;

import std.math : sin, cos;
import std.algorithm.comparison : max;
import dlib.math.vector : Vector2d, Vector3f;
import dlib.math.utils : degtorad;

@safe Entity createPlayer(EntityManager em, float walkSpeed, float headRotXMax, float headRotXMin, float headMovementSpeed, string[] bindings, PhysicsSystem physicsSystem, Camera camera = null)
{
	Entity e = new Entity(em);
	em.add(e);

	Transform* transform = e.createComponent!Transform;
	PlayerComponent* pc = e.createComponent!PlayerComponent;

	*transform = Transform.init;
	transform.position.x = 10;
	transform.position.y = 20;
	pc.headRotation = transform.rotation;
	pc.walkSpeed = walkSpeed;
	pc.headRotXMax = headRotXMax;
	pc.headRotXMin = headRotXMin;
	pc.headMovementSpeed = headMovementSpeed;
	pc.bindings = bindings;
	pc.camera = null;

	float radius = 0.5f;
	float height = 1.9f;
	float stepHeight = height / 3f;
	float scale = 3.0f;
	height = max(height - 2.0f * radius / scale, 0.1f);

	float mass = 10f;

	PhysicsComponent* phys = e.createComponent!PhysicsComponent;
	phys.rigidBody = new DynamicPlayerBody(physicsSystem, 0.5f, 1.9f, 10f, AtomicTransform(*transform));

	e.attachScript(new PlayerMovementScript(em.moxane, em.moxane.services.get!InputManager));

	return e;
}

enum PlayerBindingName
{
	walkForward,
	walkBackward,
	strafeLeft,
	strafeRight,
	debugUp,
	debugDown,
	jump,
	length
}

@safe struct PlayerComponent
{
	//Vector3f headOffset;
	Vector3f headRotation;
	//Vector3f eyeOffset;
	
	enum MotionState
	{
		still,
		ragdoll,
		crouch,
		prone,
		walk
	}
	MotionState motion;

	float walkSpeed;
	//float runSpeed;

	float headRotXMax;
	float headRotXMin;

	float headMovementSpeed;

	bool allowInput;
	@NoSerialise string[] bindings;

	@NoSerialise Camera camera;
}

@safe class PlayerMovementScript : Script
{
	InputManager input;

	this(Moxane moxane, InputManager input)
	do { 
		super(moxane);
		this.input = input;
	}

	override void onDetach() 
	{ super.onDetach; }

	override void execute()
	{
		if(input is null) return;

		PlayerComponent* pc = entity.get!PlayerComponent;
		if(pc is null) return;

		Transform* tc = entity.get!Transform;
		if(tc is null) return;

		PhysicsComponent* phys = entity.get!PhysicsComponent;
		Vector3f force = Vector3f(0, 0, 0);

		if(pc.allowInput && input.hideCursor)
		{
			Vector2d cursorMovement = input.mouseMove;
			pc.headRotation.x += cast(float)cursorMovement.y * cast(float)moxane.deltaTime * pc.headMovementSpeed;
			pc.headRotation.y += cast(float)cursorMovement.x * cast(float)moxane.deltaTime * pc.headMovementSpeed;

			if(pc.headRotation.x > pc.headRotXMax) pc.headRotation.x = pc.headRotXMax;
			if(pc.headRotation.x < pc.headRotXMin) pc.headRotation.x = pc.headRotXMin; 

			if(pc.headRotation.y > 360f) pc.headRotation.y -= 360f;
			if(pc.headRotation.y < 0f) pc.headRotation.y += 360f;
			if(tc.rotation.y > 360f) tc.rotation.y -= 360f;
			if(tc.rotation.y < 0f) tc.rotation.y += 360f;

			Vector3f movement = Vector3f(0f, 0f, 0f);
			if(input.getBindingState(pc.bindings[PlayerBindingName.walkForward])) movement.z += pc.walkSpeed;
			if(input.getBindingState(pc.bindings[PlayerBindingName.walkBackward])) movement.z -= pc.walkSpeed;

			if(input.getBindingState(pc.bindings[PlayerBindingName.strafeLeft])) movement.x -= pc.walkSpeed;
			if(input.getBindingState(pc.bindings[PlayerBindingName.strafeRight])) movement.x += pc.walkSpeed;

			if(input.getBindingState(pc.bindings[PlayerBindingName.debugUp])) movement.y += pc.walkSpeed;
			if(input.getBindingState(pc.bindings[PlayerBindingName.debugDown])) movement.y -= pc.walkSpeed;

			//if(phys is null) movement *= moxane.deltaTime;
			force = Vector3f(0, 0, 0);

			float yrot = degtorad(pc.headRotation.y);
			force.x += cos(yrot) * movement.x;
			force.z += sin(yrot) * movement.x;

			force.x += sin(yrot) * movement.z;
			force.z -= cos(yrot) * movement.z;

			force.y += movement.y;

			if(phys is null)
				tc.position = force;
			else
			{
			}
		}

		DynamicPlayerBody dpb = cast(DynamicPlayerBody)phys.rigidBody;

		dpb.yaw = pc.headRotation.y;
		/+dpb.strafe = force.x;
		dpb.vertical = force.y;
		dpb.forward = force.z;+/
		dpb.strafe = 0f;
		dpb.vertical = 0f;
		dpb.forward = 0f;
		dpb.gravity = false;
		dpb.addForce(Vector3f(force.x*3000, force.y * 3000, force.z*3000));
		dpb.update(moxane.deltaTime);
	
		if(pc.camera !is null)
		{
			pc.camera.rotation = pc.headRotation;
			pc.camera.position = tc.position + Vector3f(0, 1.3f, 0);
			pc.camera.buildView;
		}
	}
}