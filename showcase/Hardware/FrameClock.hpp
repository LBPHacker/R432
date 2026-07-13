#pragma once
#include <cstdint>

struct FrameClock
{
	using Frame = uint32_t;

	volatile Frame frame; // read-only
};
static_assert(sizeof(FrameClock) == 0x4);
