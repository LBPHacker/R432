#pragma once
#include "Hardware/FrameClock.hpp"

FrameClock::Frame Now();
void SleepUntil(FrameClock::Frame frame);
