module square.one.settings;

import std.file : exists, readText;
import std.stdio;
import std.json;
import moxana.utils.event;

class Settings {
	private string[string] settings;

	Event!(string, string) onUpdate;

	void importJson(string file) {
		if(!exists(file))
			return;

		string raw = readText(file);
		JSONValue[string] j = parseJSON(raw).object;

		foreach(i; byKeyValue(j)) {
			settings[i.key] = i.value.str;
		}
	}

	void exportJson(string file) {
		JSONValue json = parseJSON(`{ }`);

		foreach(s; byKeyValue(settings)) {
			json.object[s.key] = JSONValue(s.value);
		}

		File f = File(file, "w");
		scope(exit) f.close();

		f.write(json.toPrettyString);
		writeln(json.toPrettyString);
	}

	auto getRange() {
		return byKeyValue(settings);
	}

	string get(string name, string returnValIfNoEntry = null) 
	in {
		assert(name !is null);
	}
	body {
		string* t = name in settings;
		if(t is null)
			return returnValIfNoEntry;
		else
			return *t;
	}

	string getOrAdd(string name, string defaultVal) 
	in {
		assert(name !is null);
	}
	body {
		string* t = name in settings;
		if(t is null) {
			settings[name] = defaultVal;
			onUpdate.emit(name, defaultVal);
			return defaultVal;
		}
		else
			return *t;
	}

	void set(string name, string val)
	in {
		assert(name !is null);
	}
	body {
		settings[name] = val;
		onUpdate.emit(name, val);
	}
}