#pragma once
#include <cstdint>

struct FiltInput
{
	volatile uint32_t input; // read-only
};
static_assert(sizeof(FiltInput) == 0x4);
