#pragma once
#include <cstdint>

struct RandomSource
{
	volatile uint32_t value; // read-only
};
static_assert(sizeof(RandomSource) == 0x4);
