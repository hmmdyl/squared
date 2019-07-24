module squareone.entities.player;

import moxane.core;
import moxane.graphics.transformation;
import moxane.io;
import moxane.graphics.renderer;
import moxane.graphics.firstperson;
import squareone.entities.components.head;

import dlib.math.vector : Vector2d, Vector3f;

@safe Entity createPlayer(EntityManager em, Vector3f headOffset, float yRotBodyThreshold)
{
	Entity e = new Entity(em);
	em.add(e);

	Transform* transform = e.createComponent!Transform;
	HeadTransform* headTransform = e.createComponent!HeadTransform;

	*transform = Transform.init;
	headTransform.offset = headOffset;
	headTransform.rotation = transform.rotation;
	headTransform.yRotBodyTurnThreshold = yRotBodyThreshold;

	string[PlayerMovementScript.BindingName.length] bindings;
	e.attachScript(new PlayerMovementScript(em.moxane, em.moxane.services.get!InputManager, bindings));

	return e;
}

struct PlayerComponent
{
	Vector3f headOffset;
	Vector3f headRotation;
	Vector3f eyeOffset;
	
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
	float runSpeed;

	float headMovementSpeed;

	bool allowInput;
}

@safe class PlayerMovementScript : Script
{
	InputManager input;

	this(Moxane moxane, InputManager input, string[BindingName.length] bindings)
	do { 
		super(moxane);
		this.input = input;

		this.bindings = bindings;
		foreach(binding; this.bindings)
			this.input.boundKeys[binding] ~= &handleInputEvent;
	}

	~this()
	{
		foreach(binding; bindings)
			input.boundKeys[binding] -= &handleInputEvent;
	}

	enum BindingName
	{
		walkForward,
		walkBackward,
		strafeLeft,
		strafeRight,
		length
	}

	string[cast(int)BindingName.length] bindings;

	private void handleInputEvent(ref InputEvent e)
	{
		PlayerComponent* pc = entity.get!PlayerComponent;
		if(!pc.allowInput) return;

		/+switch(e.bindingName)
		{
			case bindings[BindingName.walkForward]:
				break;
			case bindings[BindingName.walkBackward]:
				break;
			case bindings[BindingName.strafeLeft]:
				break;
			case bindings[BindingName.strafeRight]:
				break;
		}+/

		if(e.bindingName == bindings[BindingName.walkForward])
			return;
	}

	//string jump;

	override void onDetach() 
	{
		super.onDetach;
	}

	override void execute()
	{
		//InputManager input = moxane.services.get!InputManager;
		//if(input is null) return;

		PlayerComponent* pc = entity.get!PlayerComponent;
		if(pc is null) return;
		Transform* tc = entity.get!Transform;
		if(tc is null) return;

		if(pc.allowInput && input.hideCursor)
		{
			Vector2d cursorMovement = input.mouseMove;
			pc.headRotation.x += cast(float)cursorMovement.y * cast(float)moxane.deltaTime * pc.headMovementSpeed;
			pc.headRotation.y += cast(float)cursorMovement.x * cast(float)moxane.deltaTime * pc.headMovementSpeed;
			tc.rotation = pc.headRotation;


		}
	}
}