#include "Hardware.hpp"
#include "Main.hpp"

void Main()
{
	r3Term.ResetKeyboard();
	r3Term.hrange = R3Term::MakeRange(0, 11);
	r3Term.vrange = R3Term::MakeRange(0, 7);
	r3Term.cursor = R3Term::MakeCursorPosition(0, 0);
	r3Term.nlchar = '\n';
	r3Term.colour = R3Term::MakeColour(0, 15);
	r3Term.scrollmask = 0xFFFFFFFF;
	for (uint32_t i = 0; i < 8; ++i)
	{
		r3Term.Scrollprint(R3Term::enableScrollmask | R3Term::rowOriented, ' ');
	}
	while (true)
	{
		auto got = r3Term.ReadBlocking();
		r3Term.Scrollprint(R3Term::simpleTerminal, got);
	}
}
