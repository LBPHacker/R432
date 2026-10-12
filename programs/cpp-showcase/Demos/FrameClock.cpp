#include "FrameClock.hpp"
#include "Print.hpp"
#include "Hardware.hpp"

void DemoFrameClock()
{
	PrintClear();
	PrintWithBreaks("This demo prints in hexadecimal the current 32-bit frame number read from the frame clock whenever you press Space. Press any other key to exit.");
	PrintNewline();
	while (true)
	{
		auto ch = terminal.ReadBlocking();
		if (ch != ' ')
		{
			break;
		}
		PrintNumber16(frameClock.frame);
		PrintNewline();
	}
}
