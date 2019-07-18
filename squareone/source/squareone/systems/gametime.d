module squareone.systems.gametime;

struct VirtualTime
{
	@nogc nothrow:
	int hour, minute, second;

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
		second++;
		if(second > 59)
		{
			incMinute;
			second = 0;
		}
	}

	void incMinute()
	{
		minute++;
		if(minute > 59)
		{
			incHour;
			minute = 0;
		}
	}

	void incHour()
	{
		hour++;
		if(hour > 23)
			hour = 0;
	}

	@property float decimal() const 
	{
		enum inv6060 = 1 / 60f / 60f;
		enum inv60 = 1 / 60;
		float sec = cast(float)second * inv6060;
		float min = cast(float)minute * inv60;
		float t = cast(float)hour + min + sec;
		return t;
	}
}