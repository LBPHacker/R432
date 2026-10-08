#pragma once
#include <cstdint>

struct FiltOutput
{
	volatile uint32_t output; // write-only
};
static_assert(sizeof(FiltOutput) == 0x4);
