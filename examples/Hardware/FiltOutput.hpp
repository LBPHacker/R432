#pragma once
#include <stdint.h>

struct FiltOutput
{
	volatile uint32_t output; // write-only
};
static_assert(sizeof(FiltOutput) == 0x4);
