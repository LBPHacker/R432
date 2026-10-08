#include "Time.hpp"
#include "Hardware.hpp"

FrameClock::Frame Now()
{
	return frameClock.frame;
}

void SleepUntil(FrameClock::Frame frame)
{
	while (Now() < frame);
}
