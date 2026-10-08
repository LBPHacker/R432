#include "Menu.hpp"
#include "Print.hpp"
#include "Hardware.hpp"

void Menu(const char *title, const MenuOption *options)
{
	PrintClear();
	PrintWithBreaks(title);
	PrintNewline();
	int32_t itemCount = 0;
	for (auto *curr = options; curr->func; ++curr)
	{
		terminal.Scrollprint(Terminal::simpleTerminal, '1' + itemCount);
		terminal.Scrollprint(Terminal::simpleTerminal, ')');
		terminal.Scrollprint(Terminal::simpleTerminal, ' ');
		printCursorX += 3;
		PrintWithBreaks(curr->title);
		PrintNewline();
		itemCount += 1;
	}
	int32_t selected;
	while (true)
	{
		auto ch = int32_t(GetCharBlink());
		if (ch >= '1' && ch <= '0' + itemCount)
		{
			selected = ch - '1';
			break;
		}
	}
	options[selected].func();
}
