#include "RandomSource.hpp"
#include "Print.hpp"
#include "Hardware.hpp"

void DemoRandomSource()
{
	PrintClear();
	PrintWithBreaks("This demo prints in hexadecimal a random 32-bit number read from the random source whenever you press Space. Press any other key to exit.");
	PrintNewline();
	while (true)
	{
		auto ch = terminal.ReadBlocking();
		if (ch != ' ')
		{
			break;
		}
		PrintNumber16(randomSource.value);
		PrintNewline();
	}
}
