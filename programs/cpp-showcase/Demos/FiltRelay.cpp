#include "FiltRelay.hpp"
#include "Print.hpp"
#include "Hardware.hpp"

void DemoFiltRelay()
{
	PrintClear();
	PrintWithBreaks("This demo copies the states of the FILT inputs (right box) onto the FILT outputs (left box). Use PROP to configure the inputs and the signs to read them. Press any key to exit.");
	PrintNewline();
	while (true)
	{
		if (terminal.input)
		{
			break;
		}
		filtOutput.output = filtInput.input;
	}
}
