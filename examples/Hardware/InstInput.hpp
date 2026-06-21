#pragma once
#include <stdint.h>

struct InstInput
{
	volatile uint32_t input; // read-only
};
static_assert(sizeof(InstInput) == 0x4);
