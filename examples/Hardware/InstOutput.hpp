#pragma once
#include <stdint.h>

struct InstOutput
{
	volatile uint32_t output; // write-only
};
static_assert(sizeof(InstOutput) == 0x4);
