#include <stdint.h>

// implement these as needed: https://gcc.gnu.org/onlinedocs/gccint/Integer-library-routines.html

uint32_t __udivsi3(uint32_t a, uint32_t b)
{
	int32_t i = 32;
#define REDUCE(k) if (!(a & (((1U << (k)) - 1U) << (32 - k)))) { i -= k; a <<= k; }
	REDUCE(16)
	REDUCE(8)
	REDUCE(4)
	REDUCE(2)
	REDUCE(1)
#undef REDUCE
	uint32_t h = 0;
	uint32_t r = 0;
	for (; i; --i)
	{
		h = (h << 1) | (a >> 31);
		a <<= 1;
		r <<= 1;
		if (h >= b)
		{
			h -= b;
			r += 1;
		}
	}
	return r;
}

uint32_t __umodsi3(uint32_t a, uint32_t b)
{
	return a - __udivsi3(a, b) * b;
}

int32_t __divsi3(int32_t a, int32_t b)
{
	bool flip = false;
	if (a < 0) { a = -a; flip = !flip; };
	if (b < 0) { b = -b; flip = !flip; };
	int32_t r = (int32_t)__udivsi3((uint32_t)a, (uint32_t)b);
	if (flip) { r = -r; };
	return r;
}

int32_t __modsi3(int32_t a, int32_t b)
{
	return a - __divsi3(a, b) * b;
}
