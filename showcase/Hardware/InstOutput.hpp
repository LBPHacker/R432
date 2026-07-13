#pragma once
#include <cstdint>

struct InstOutput
{
	volatile uint32_t output; // write-only
};
static_assert(sizeof(InstOutput) == 0x4);
