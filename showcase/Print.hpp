#pragma once
#include <cstdint>

extern uint32_t printCursorX;
extern uint32_t printCursorY;
extern uint32_t printColourFg;
extern uint32_t printColourBg;

void PrintInit();
void PrintClear();
void PrintWithBreaks(const char *str);
uint32_t GetCharBlink();
void PrintNewline();
void PrintNumber16(uint32_t n);
