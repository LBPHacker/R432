#include "Echo.hpp"
#include "Print.hpp"
#include "Hardware.hpp"

void DemoEcho()
{
	PrintClear();
	PrintWithBreaks("This demo echos back everything you type. Press Backspace to exit.");
	PrintNewline();
	while (true)
	{
		auto ch = terminal.ReadBlocking();
		if (ch == '\b')
		{
			break;
		}
		terminal.Scrollprint(Terminal::simpleTerminal, ch);
	}
}
