#include "Hardware.hpp"
#include "Main.hpp"

void Main()
{
	terminal.ResetKeyboard();
	terminal.hrange = Terminal::MakeRange(0, 11);
	terminal.vrange = Terminal::MakeRange(0, 7);
	terminal.cursor = Terminal::MakeCursorPosition(0, 0);
	terminal.nlchar = '\n';
	terminal.colour = Terminal::MakeColour(0, 15);
	terminal.scrollmask = 0xFFFFFFFF;
	for (uint32_t i = 0; i < 8; ++i)
	{
		terminal.Scrollprint(Terminal::enableScrollmask, ' ');
	}
	while (true)
	{
		auto got = terminal.ReadBlocking();
		terminal.Scrollprint(Terminal::simpleTerminal, got);
	}
}
