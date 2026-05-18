#include "Hardware.hpp"
#include "Main.hpp"
#include <utility>

static void PrintOne(const char *ch)
{
	for (auto *p = ch; *p; ++p)
	{
		r4Term.Scrollprint(R4Term::simpleTerminal, *p);
	}
}

static void PrintOne(uint32_t number)
{
	bool seenNonzero = false;
	auto print1 = [&](uint32_t part) {
		seenNonzero |= part;
		if (seenNonzero)
		{
			r4Term.Scrollprint(R4Term::simpleTerminal, char(part + '0'));
		}
	};
	auto print2 = [&](uint32_t part) {
		print1(part / 10U);
		print1(part % 10U);
	};
	auto print4 = [&](uint32_t part) {
		print2(part / 100U);
		print2(part % 100U);
	};
	print2(number / 100000000U);
	auto lo8 = number % 100000000U;
	print4(lo8 / 10000U);
	print4(lo8 % 10000U);
	if (!seenNonzero)
	{
		r4Term.Scrollprint(R4Term::simpleTerminal, '0');
	}
}

template<class ...Args>
static void Print(Args &&...args)
{
	[[maybe_unused]] auto unused = std::initializer_list<int>{ (PrintOne(args), 0)... };
}

void Main()
{
	r4Term.hrange = R4Term::MakeRange(0, 11);
	r4Term.vrange = R4Term::MakeRange(0, 7);
	r4Term.cursor = R4Term::MakeCursorPosition(0, 0);
	r4Term.nlchar = '\n';
	r4Term.colour = R4Term::MakeColour(0, 15);
	r4Term.scrollmask = 0xFFFFFFFF;
	for (uint32_t i = 0; i < 8; ++i)
	{
		r4Term.Scrollprint(R4Term::enableScrollmask, ' ');
	}

	uint32_t number = 2;
	uint32_t maxDivisor = 1;
	uint32_t nextThreshold = 4;
	while (true)
	{
		if (nextThreshold == number)
		{
			maxDivisor += 1;
			nextThreshold += 2 * maxDivisor + 1;
		}
		([&]() {
			for (uint32_t divisor = 2; divisor <= maxDivisor; ++divisor)
			{
				if (!(number % divisor))
				{
					return;
				}
			}
			Print(number, " ");
		})();
		number += 1;
	}
}
