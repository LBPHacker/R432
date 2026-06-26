#pragma once
#include <stdint.h>

struct RandomSource
{
	volatile uint32_t value; // read-only
};
static_assert(sizeof(RandomSource) == 0x4);
