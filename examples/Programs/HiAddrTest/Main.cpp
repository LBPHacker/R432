#include "Main.hpp"
#include <stdint.h>
#include <stdlib.h>

uint32_t bruh[2];

void Main()
{
	bruh[0x0000000] = UINT32_C(0xDEADBEEF);
	__asm__ __volatile__("":::"memory");
	bruh[0x0000001] = UINT32_C(0xCAFEBABE);
	// bruh[0x1000001] = UINT32_C(0xCAFEBABE); // uncomment to get a warning and a hang
	exit(5);
}
