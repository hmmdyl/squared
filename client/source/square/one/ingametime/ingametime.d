module square.one.ingametime.ingametime;

import std.conv;

import std.math;
import gfm.math.vector : vec3f;

import moxana.hierarchy.world;

class TimeWorldDescriptor : IWorldDescriptor {
	@property string technicalName() { return TimeWorldDescriptor.stringof; }

	World world;

	private IngameTime time_;
	@property IngameTime time() { return time_; }
	@property void time(IngameTime t) { time_ = t; }

	this(World world, IngameTime startTime = IngameTime(6, 0)) {
		this.world = world;
		this.time_ = startTime;
	}

	private float leftOverTime = 0f;
	enum float irlSecondsToGameSeconds = 1f / 60f;

	void update(double dt) {
		float n = leftOverTime + cast(float)dt;
		float ts = n / irlSecondsToGameSeconds;
		int ti = cast(int)ts;

		if(ti > 0) {
			foreach(tic; 0 .. ti)
				time.incSecond;
			n -= (ti * irlSecondsToGameSeconds);
			leftOverTime = n;
		}
		else
			leftOverTime = n;
	}

	override string toString() {
		return time.toString;
	}
}

struct IngameTime {
	private int hour_, minute_, second_;

	@property int hour() const { return hour_; }
	@property void hour(int h) {
		if(h < 0) h = 0;
		if(h > 23) h = 23;
		hour_ = h;
	}

	@property int minute() const { return minute_; }
	@property void minute(int m) {
		if(m < 0) m = 0;
		if(m > 59) m = 59;
		minute_ = m;
	}

	@property int second() const { return second_; }
	@property void second(int s) {
		if(s < 0) s = 0;
		if(s > 59) s = 59;
		second_ = s;
	}

	this(int hour, int minute, int second = 0) {
		this.hour = hour;
		this.minute = minute;
		this.second = second;
	}

	void incSecond() {
		second_++;
		if(second_ > 59) {
			incMinute;
			second_ = 0;
		}
	}

	void incMinute() {
		minute_++;
		if(minute_ > 59) {
			incHour;
			minute_ = 0;
		}
	}

	void incHour() {
		hour_++;
		if(hour_ > 23) {
			hour_ = 0;
		}
	}

	private enum float inv12 = 1f / 12f;
	private enum float inv12Pi = inv12 * PI;

	string toString() const {
		return "Time: " ~ to!string(hour) ~ ':' ~ to!string(minute) ~ ':' ~ to!string(second);
	}

	vec3f timeToSun() {
		float time24 = asDecimal;

		return vec3f(
			0,
			-cos(inv12Pi * time24),
			sin(inv12Pi * time24));
	}

	float asDecimal() const {
		float sec = cast(float)second_ / 60f / 60f;
		float min = cast(float)minute_ / 60.0f;
		float time24 = cast(float)hour_ + min + sec;
		return time24;
	}

	int opCmp(ref const IngameTime t) const {
		float time24 = asDecimal;
		float ttime24 = t.asDecimal;

		if(time24 < ttime24)
			return -1;
		if(time24 > ttime24)
			return 1;

		return 0;
	}
}