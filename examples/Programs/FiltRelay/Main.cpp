#include "Hardware.hpp"
#include "Main.hpp"

void Main()
{
	while (true)
	{
		filtOutput.output = filtInput.input;
		instOutput.output = instInput.input;
	}
}
