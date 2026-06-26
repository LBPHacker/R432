#pragma once
#include <stdint.h>

struct FrameClock
{
	volatile uint32_t frame; // read-only
};
static_assert(sizeof(FrameClock) == 0x4);
