#include "Hardware.hpp"
#include "Time.hpp"

uint32_t printCursorX;
uint32_t printCursorY;
uint32_t printColourFg;
uint32_t printColourBg;

void PrintInit()
{
	terminal.ResetKeyboard();
	terminal.hrange = Terminal::MakeRange(0, terminalWidth - 1);
	terminal.vrange = Terminal::MakeRange(0, terminalHeight - 1);
	terminal.cursor = Terminal::MakeCursorPosition(0, 0);
	terminal.nlchar = '\n';
	terminal.scrollmask = 0xFFFFFFFF;
}

void PrintClear()
{
	printColourFg = 15;
	printColourBg = 1;
	printCursorX = 0;
	printCursorY = 0;
	terminal.colour = Terminal::MakeColour(printColourFg, printColourBg);
	for (uint32_t i = 0; i < 8; ++i)
	{
		terminal.Scrollprint(Terminal::enableScrollmask, ' ');
	}
}

void PrintWithBreaks(const char *str)
{
	terminal.colour = Terminal::MakeColour(printColourFg, printColourBg);
	terminal.cursor = Terminal::MakeCursorPosition(printCursorX, printCursorY);
	auto *wordBegin = str;
	auto firstWord = true;
	while (true)
	{
		while (*wordBegin == ' ')
		{
			++wordBegin;
		}
		auto *wordEnd = wordBegin;
		bool foundEnd = false;
		while (true)
		{
			if (!*wordEnd)
			{
				foundEnd = true;
				break;
			}
			if (*wordEnd == ' ')
			{
				break;
			}
			++wordEnd;
		}
		uint32_t wordSize = wordEnd - wordBegin;
		auto fits = printCursorX + wordSize + (firstWord ? 0 : 1) <= terminalWidth;
		if (fits)
		{
			if (firstWord)
			{
				firstWord = false;
			}
			else
			{
				terminal.Scrollprint(Terminal::simpleTerminal, ' ');
				++printCursorX;
			}
		}
		else
		{
			terminal.Scrollprint(Terminal::simpleTerminal, '\n');
			printCursorX = 0;
			if (printCursorY < terminalHeight - 1)
			{
				++printCursorY;
			}
		}
		for (auto *curr = wordBegin; curr != wordEnd; ++curr)
		{
			if (printCursorX == terminalWidth)
			{
				printCursorX = 0;
				if (printCursorY < terminalHeight - 1)
				{
					++printCursorY;
				}
			}
			terminal.Scrollprint(Terminal::simpleTerminal, *curr);
			++printCursorX;
		}
		if (foundEnd)
		{
			break;
		}
		firstWord = printCursorX == 0;
		wordBegin = wordEnd;
	}
}

uint32_t GetCharBlink()
{
	uint32_t ch = 0;
	constexpr uint32_t sleepFrames = 30;
	auto now = Now();
	auto bg = printColourBg;
	auto fg = printColourFg;
	while (true)
	{
		ch = terminal.input;
		if (ch)
		{
			break;
		}
		terminal.colour = Terminal::MakeColour(fg, bg);
		terminal.cursor = Terminal::MakeCursorPosition(printCursorX, printCursorY);
		terminal.Scrollprint(Terminal::termMode, ' ');
		auto then = now + sleepFrames;
		SleepUntil(then);
		now = then;
		{
			auto temp = bg;
			bg = fg;
			fg = temp;
		}
	}
	return ch;
}

void PrintNewline()
{
	terminal.Scrollprint(Terminal::simpleTerminal, '\n');
	printCursorX = 0;
	if (printCursorY < terminalHeight - 1)
	{
		++printCursorY;
	}
}

void PrintNumber16(uint32_t n)
{
	char buf[9];
	for (int32_t i = 0; i < 8; ++i)
	{
		constexpr char lut16[] = "0123456789ABCDEF";
		buf[7 - i] = lut16[(n >> (i * 4)) & 15];
	}
	buf[8] = 0;
	PrintWithBreaks(buf);
}
