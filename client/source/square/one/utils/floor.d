module square.one.utils.floor;

/// floor the division of an integer
int ifloordiv(int n, int divisor) {
	if(n >= 0)
		return n / divisor;
	else
		return ~(~n / divisor);
}