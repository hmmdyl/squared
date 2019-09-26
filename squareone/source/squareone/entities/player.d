module squareone.entities.player;

import moxane.core;
import moxane.io;
import moxane.graphics.renderer;
import moxane.graphics.firstperson;
import moxane.network.semantic;

import std.math : cos, sin;
import dlib.math.vector : Vector2d, Vector3f;
import dlib.math.utils : degtorad;

@safe Entity createPlayer(EntityManager em, float walkSpeed, float headRotXMax, float headRotXMin, float headMovementSpeed, string[] bindings, Camera camera = null)
{
	Entity e = new Entity(em);
	em.add(e);

	Transform* transform = e.createComponent!Transform;
	PlayerComponent* pc = e.createComponent!PlayerComponent;

	*transform = Transform.init;
	pc.headRotation = transform.rotation;
	pc.walkSpeed = walkSpeed;
	pc.headRotXMax = headRotXMax;
	pc.headRotXMin = headRotXMin;
	pc.headMovementSpeed = headMovementSpeed;
	pc.bindings = bindings;
	pc.camera = null;

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

		if(pc.allowInput && input.hideCursor)
		{
			Transform* tc = entity.get!Transform;
			if(tc is null) return;

			Vector2d cursorMovement = input.mouseMove;
			pc.headRotation.x += cast(float)cursorMovement.y * cast(float)moxane.deltaTime * pc.headMovementSpeed;
			pc.headRotation.y += cast(float)cursorMovement.x * cast(float)moxane.deltaTime * pc.headMovementSpeed;
			tc.rotation = pc.headRotation;

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

			movement *= moxane.deltaTime;

			float yrot = degtorad(tc.rotation.y);
			tc.position.x += cos(yrot) * movement.x;
			tc.position.z += sin(yrot) * movement.x;

			tc.position.x += sin(yrot) * movement.z;
			tc.position.z -= cos(yrot) * movement.z;

			tc.position.y += movement.y;

			if(pc.camera !is null)
			{
				pc.camera.rotation = pc.headRotation;
				pc.camera.position = tc.position;
				pc.camera.buildView;
			}
		}
	}
}