#pragma once
#include <stdint.h>

struct R4Term
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

	using PixelPosition = uint32_t;
	static constexpr PixelPosition MakePixelPosition(uint32_t column, uint32_t row)
	{
		return column | (row << 8);
	}

	volatile uint32_t input;
	volatile Range hrange;
	volatile Range vrange;
	volatile CursorPosition cursor;
	volatile uint32_t nlchar;
	volatile Colour colour;
	volatile uint32_t scrollmask;
	volatile uint32_t plotpix;
	volatile uint32_t padding1[0x78];
	volatile uint32_t scrollprint[0x80];
	volatile uint32_t beginbitmap[0x100];
	volatile uint32_t charmem[0x200];
	volatile uint32_t endbitmap[0x400];

	using ScrollprintFlag = uint32_t;
	static constexpr ScrollprintFlag posInData        = UINT32_C(1) << 6;
	static constexpr ScrollprintFlag enableNlchar     = UINT32_C(1) << 5;
	static constexpr ScrollprintFlag termModeScroll   = UINT32_C(1) << 4;
	static constexpr ScrollprintFlag enableScrollmask = UINT32_C(1) << 3;
	static constexpr ScrollprintFlag columnOriented   = UINT32_C(1) << 2;
	static constexpr ScrollprintFlag colourInData     = UINT32_C(1) << 1;
	static constexpr ScrollprintFlag termMode         = UINT32_C(1) << 0;
	static constexpr auto simpleTerminal = enableNlchar | termModeScroll | termMode;
	inline void Scrollprint(ScrollprintFlag flags, uint32_t value)
	{
		scrollprint[flags] = value;
	}

	inline void Plotpix(uint32_t colour, PixelPosition position)
	{
		plotpix = position | (colour << 16);
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
static_assert(sizeof(R4Term) == 0x2000);
