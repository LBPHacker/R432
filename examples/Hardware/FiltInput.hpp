#pragma once
#include <stdint.h>

struct FiltInput
{
	volatile uint32_t input; // read-only
};
static_assert(sizeof(FiltInput) == 0x4);
