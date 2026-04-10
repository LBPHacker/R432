#pragma once
#include <stdint.h>

struct R3Term
{
	using Range = uint32_t;
	static constexpr Range MakeRange(uint32_t first, uint32_t last)
	{
		return first | (last << 5);
	}

	using Colour = uint32_t;
	static constexpr Colour MakeColour(uint32_t background, uint32_t foreground)
	{
		return background | (foreground << 4);
	}

	using CursorPosition = uint32_t;
	static constexpr CursorPosition MakeCursorPosition(uint32_t column, uint32_t row)
	{
		return column | (row << 5);
	}

	volatile uint32_t scrollprint[0x40];
	volatile uint32_t char0odd;
	volatile uint32_t char0even;
	volatile Range hrange;
	volatile Range vrange;
	volatile CursorPosition cursor;
	volatile uint32_t nlchar;
	volatile Colour colour;
	volatile uint32_t scrollmask;
	volatile uint32_t padding1[0x18];
	volatile uint32_t plotpix[0x10];
	volatile uint32_t padding2[0x0F];
	volatile uint32_t input; // could be anywhere really, the entire range maps to this register

	using ScrollprintFlag = uint32_t;
	static constexpr ScrollprintFlag enableNlchar     = UINT32_C(1) << 5;
	static constexpr ScrollprintFlag termModeScroll   = UINT32_C(1) << 4;
	static constexpr ScrollprintFlag enableScrollmask = UINT32_C(1) << 3;
	static constexpr ScrollprintFlag rowOriented      = UINT32_C(1) << 2;
	static constexpr ScrollprintFlag colourInData     = UINT32_C(1) << 1;
	static constexpr ScrollprintFlag termMode         = UINT32_C(1) << 0;

	static constexpr auto simpleTerminal = enableNlchar | termModeScroll | rowOriented | termMode;

	inline void Scrollprint(ScrollprintFlag flags, uint32_t value)
	{
		scrollprint[flags] = value;
	}

	using PixelPosition = uint32_t;
	static constexpr PixelPosition MakePixelPosition(uint32_t column, uint32_t row)
	{
		return column | (row << 8);
	}

	inline void Plotpix(uint32_t colour, PixelPosition position)
	{
		plotpix[colour] = position;
	}

	inline void ResetKeyboard()
	{
		[[maybe_unused]] uint32_t unused = input;
	}

	inline uint32_t ReadBlocking()
	{
		uint32_t got;
		while (true)
		{
			got = input;
			if (got & 0xFF)
			{
				break;
			}
		}
		return got;
	}
};
static_assert(sizeof(R3Term) == 0x200);
