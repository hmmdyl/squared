module square.one.utils.gametime;

import std.datetime.stopwatch;

private __gshared StopWatch timeRun;

public Duration getTimeRun() { return timeRun.peek(); }

shared static this() {
	timeRun = StopWatch(AutoStart.yes);
}