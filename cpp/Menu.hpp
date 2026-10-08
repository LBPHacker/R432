#pragma once

struct MenuOption
{
	const char *title;
	void (*func)();
};
void Menu(const char *title, const MenuOption *options);
