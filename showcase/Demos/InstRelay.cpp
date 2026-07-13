#include "InstRelay.hpp"
#include "Print.hpp"
#include "Hardware.hpp"

void DemoInstRelay()
{
	PrintClear();
	PrintWithBreaks("This demo copies the states of the INST inputs (right box) onto the INST outputs (left box). Use SPRK to spark the inputs and turn deco off to see the outputs. Press any key to exit.");
	PrintNewline();
	while (true)
	{
		if (terminal.input)
		{
			break;
		}
		instOutput.output = instInput.input;
	}
}
