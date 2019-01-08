module square.one.utils.objpool;

import std.container.array;
import std.traits;

struct ObjectPool(T) {
	public T delegate() constructor;

	public bool expands;
	private Array!T arr;
	private Object syncObj;

	public this(T delegate() constructor, int defaultAmount = 2, bool expands = true) {
		this.constructor = constructor;
		this.expands = expands;
		this.syncObj = new Object();

		arr.reserve(defaultAmount);

		foreach(int i; 0 .. defaultAmount) {
			give(constructor());
		}
	}

	public T get() {
		synchronized(syncObj) {
			if(arr.length == 0) 
			{
				if(expands) {
					import std.stdio;
					writeln("Allocating.");
					return constructor();
				}
				else return null;
			}

			T item = arr.back;
			arr.removeBack;
			return item;
		}
	}

	public void give(T item) 
	in { assert(item !is null); }
	body {
		synchronized(syncObj) {
			arr.insertBack(item);
		}
	}
}