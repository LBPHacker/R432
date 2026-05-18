#include "Hardware.hpp"
#include "Main.hpp"

void Main()
{
	r4Term.ResetKeyboard();
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
	while (true)
	{
		auto got = r4Term.ReadBlocking();
		r4Term.Scrollprint(R4Term::simpleTerminal, got);
	}
}
