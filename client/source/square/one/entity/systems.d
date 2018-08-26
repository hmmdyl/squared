module square.one.entity.systems;

import entitysysd;

import square.one.entity.components;

class ScriptSystem : System {
	protected override void run(EntityManager entities, EventManager events, Duration dt) {
		foreach(Entity entity, ScriptComponent* scr; entities.entitiesWith!ScriptComponent) {
			if(!scr.started) {
				if(scr.onStart !is null)
					scr.onStart(entity);
				scr.started = true;
			}

			if(scr.onExecute !is null)
				scr.onExecute(entity);
		}
	}
}