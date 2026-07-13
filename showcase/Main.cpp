#include "Menu.hpp"
#include "Print.hpp"
#include "Demos/Echo.hpp"
#include "Demos/RandomSource.hpp"
#include "Demos/FrameClock.hpp"
#include "Demos/FiltRelay.hpp"
#include "Demos/InstRelay.hpp"

extern "C" [[noreturn]] void Main()
{
	PrintInit();
	while (true)
	{
		static const MenuOption mainMenu[] = {
			{ "Echo"     , DemoEcho         },
			{ "RandomSrc", DemoRandomSource },
			{ "FrameClk" , DemoFrameClock   },
			{ "FiltRelay", DemoFiltRelay    },
			{ "InstRelay", DemoInstRelay    },
			{ nullptr, nullptr },
		};
		Menu("Hello from C++, please pick a demo:", mainMenu);
	}
}
