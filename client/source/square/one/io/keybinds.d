module square.one.io.keybinds;

import moxana.utils.event;
import moxana.io.kbm;
import moxana.io.window;
import square.one.settings;

import std.conv : to;

class KeyBinds {
	private Event!(ButtonAction)[string] commands;
	private string[int] keyToCommand;
	private int[string] commandToKey;

	Window window;
	Settings settings;

	this(Window window, Settings settings) {
		this.window = window;
		this.settings = settings;
		this.settings.onUpdate.add(&onSettingsUpdate);

		this.window.onMouseButton.add(&onMouseButton);
		this.window.onKey.add(&onKey);
	}

	void registerKeyBind(string command, Keys defaultKey) { registerKeyBind(command, cast(int)defaultKey); }
	void registerKeyBind(string command, MouseButton defaultButton) { registerKeyBind(command, cast(int)defaultButton); }

	private void registerKeyBind(string command, int k) {
		int* p = command in commandToKey;
		if(p !is null) {
			keyToCommand.remove(*p);
		}

		keyToCommand[k] = command;
		commandToKey[command] = k;
		commands[command] = Event!ButtonAction();
	}

	private void onSettingsUpdate(string name, string value) { getBindings(); }

	int getOrAdd(string name, int defaultValue) {
		int* p = name in commandToKey;
		if(p is null) {
			registerKeyBind(name, defaultValue);
			return defaultValue;
		}
		else return *p;
	}

	bool ignore = false;
	void getBindings() {
		if(ignore) return;

		clear(keyToCommand);

		foreach(setting; settings.getRange()) {
			if((setting.key in commandToKey) !is null) {
				registerKeyBind(setting.key, to!int(setting.value));
			}
		}
	}

	void exportToSettings() {
		ignore = true;

		foreach(bind; byKeyValue(keyToCommand)) {
			settings.set(bind.value, to!string(bind.key));
		}

		ignore = false;
	}

	private void onKey(Window win, Keys key, ButtonAction a) { 
		string* commName = cast(int)key in keyToCommand;
		if(commName !is null) {
			commands[*commName].emit(a);
		}
	}
	private void onMouseButton(Window win, MouseButton mouseb, ButtonAction a) {
		string* commName = cast(int)mouseb in keyToCommand;
		if(commName !is null) {
			commands[*commName].emit(a);
		}
	}

	void connect(string command, void delegate(ButtonAction b) del) { commands[command].add(del); }
	void disconnect(string command, void delegate(ButtonAction b) del) { commands[command].remove(del); }
}