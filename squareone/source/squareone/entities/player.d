module squareone.entities.player;

import moxane.core;
import moxane.graphics.transformation;
import moxane.io;
import moxane.graphics.renderer;
import moxane.graphics.firstperson;
import squareone.entities.components.head;

import dlib.math.vector : Vector2d, Vector3f;

@safe Entity createPlayer(EntityManager em, float headOffset)
{
	Entity e = new Entity(em);
	em.add(e);

	Transform* transform = e.createComponent!Transform;
	HeadTransform* headTransform = e.createComponent!HeadTransform;

	*transform = Transform.init;
	headTransform.transform = Transform.init;
	headTransform.position.y = transform.position.y + headOffset;

	e.attachScript(new PlayerMovementScript(em.moxane));

	return e;
}

@safe class PlayerMovementScript : Script
{
	this(Moxane moxane) 
	{ 
		super(moxane); 
	}

	FirstPersonCamera camera;

	override void execute()
	{
		assert(hasComponents!(Transform, HeadTransform)(entity));

		Window win = moxane.services.get!Window;
		
		if(win.isFocused && win.isMouseButtonDown(MouseButton.right))
		{
			Vector2d cursor = win.cursorPos;
			Vector2d c = cursor - cast(Vector2d)win.size / 2;
			win.cursorPos = cast(Vector2d)win.size / 2;

			Vector3f rot;
			rot.x = cast(float)c.y * cast(float)moxane.deltaTime * 10;
			rot.y = cast(float)c.x * cast(float)moxane.deltaTime * 10;
			rot.z = 0f;
	
			Transform* tr = entity.get!Transform;
			tr.rotation.y += rot.y;
			if(tr.rotation.y > 360f) tr.rotation.y -= 360f;
			if(tf.rotation.y < 0f) tr.rotation.y += 360f;



			camera.rotate(rot);

			Vector3f a = Vector3f(0f, 0f, 0f);
			if(win.isKeyDown(Keys.w)) a.z += 1f;
			if(win.isKeyDown(Keys.s)) a.z -= 1f;
			if(win.isKeyDown(Keys.a)) a.x -= 1f;
			if(win.isKeyDown(Keys.d)) a.x += 1f;
			if(win.isKeyDown(Keys.q)) a.y -= 1f;
			if(win.isKeyDown(Keys.e)) a.y += 1f;

			camera.moveOnAxes(a * moxane.deltaTime);
		}
	}
}