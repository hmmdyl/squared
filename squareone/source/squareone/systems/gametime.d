module squareone.systems.gametime;

import moxane.core;

import cerealed;

class TimeSystem : System
{
	Moxane moxane;
	EntityManager entityManager;

	this(Moxane moxane, EntityManager entityManager) 
	in { assert(moxane !is null); } out { assert(entityManager !is null); }
	do { super(moxane, entityManager); }

	override void update()
	{
		foreach(Entity entity; entityManager.entitiesWith!TimeComponent)
		{
			TimeComponent* tc = entity.get!TimeComponent;
			if(tc is null) continue;

			float n = tc.remainingTime + moxane.deltaTime;
			float ts = n / tc.secondMap;
			int ti = cast(int)ts;
			if(ti > 0)
			{
				foreach(tic; 0 .. ti) tc.time.incSecond;
				n -= (ti * tc.secondMap);
			}
			tc.remainingTime = n;
		}
	}
}

struct TimeComponent
{
	VirtualTime time;
	@NoCereal float remainingTime;
	float secondMap;

	void update(float deltaTime)
	{
		float n = remainingTime + deltaTime;
		float ts = n / secondMap;
		int ti = cast(int)ts;
		if(ti > 0)
		{
			foreach(tic; 0 .. ti) time.incSecond;
			n -= (ti * secondMap);
		}
		remainingTime = n;
	}
}

struct VirtualTime
{
	@safe @nogc nothrow:

	int hour, minute, second;

	enum maxHour = 24;
	enum maxMinute = 60;
	enum maxSecond = 60;

	invariant
	{
		assert(hour >= 0 && hour < 24);
		assert(minute >= 0 && minute < 60);
		assert(second >= 0 && second < 60);
	}

	this(int hour, int minute, int second = 0)
	{
		this.hour = hour;
		this.minute = minute;
		this.second = second;
	}

	void incSecond()
	{
		//second++;
		if(second >= 59)
		{
			incMinute;
			second = 0;
		}
		else second++;
	}

	void incMinute()
	{
		//minute++;
		if(minute >= 59)
		{
			incHour;
			minute = 0;
		}
		else minute++;
	}

	void incHour()
	{
		//hour++;
		if(hour >= 23)
			hour = 0;
		else hour++;
	}

	void decHour()
	{
		if(hour == 0) hour = 23;
		else hour--;
	}

	void decMinute()
	{
		if(minute == 0)
		{
			decHour;
			minute = 59;
		}
		else minute--;
	}

	@property float decimal() const 
	{
		enum inv6060 = 1 / 60f / 60f;
		enum inv60 = 1 / 60f;
		float sec = cast(float)second * inv6060;
		float min = cast(float)minute * inv60;
		float t = cast(float)hour + min + sec;
		return t;
	}
}