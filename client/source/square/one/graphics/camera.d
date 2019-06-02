module square.one.graphics.camera;

import moxana.graphics.view;

import dlib.math;
import std.math;

public class Camera {
	public View view;

	public this(View view) {
		this.view = view;
	}

	public void moveOnAxes(Vector3f vec) {
		// strafe
		float yr = degtorad(view.rotation.y);
		view.position.x += cos(yr) * vec.x;
		view.position.z += sin(yr) * vec.x;

		// forward
		view.position.x += sin(yr) * vec.z;
		view.position.z -= cos(yr) * vec.z;

		view.position.y += vec.y;
	}

	public void rotate(Vector3f vec) {
		view.rotation.x += vec.x;
		view.rotation.y += vec.y;
		view.rotation.z += vec.z;

		if(view.rotation.x > 90f)
			view.rotation.x = 90f;
		if(view.rotation.x < -90f)
			view.rotation.x = -90f;
		if(view.rotation.y > 360f)
			view.rotation.y -= 360f;
		if(view.rotation.y < 0f)
			view.rotation.y += 360f;
	}
}