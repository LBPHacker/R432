#pragma once
#include "Terminal.hpp"
#include "FiltInput.hpp"
#include "FiltOutput.hpp"
#include "InstInput.hpp"
#include "InstOutput.hpp"
#include "RandomSource.hpp"
#include "FrameClock.hpp"

extern Terminal terminal;
constexpr int32_t terminalWidth = 12;
constexpr int32_t terminalHeight = 8;

extern FiltInput filtInput;
extern FiltOutput filtOutput;
extern InstInput instInput;
extern InstOutput instOutput;
extern RandomSource randomSource;
extern FrameClock frameClock;
