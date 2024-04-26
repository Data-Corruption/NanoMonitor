#include <pdh.h>
#include <pdhmsg.h>
#include <windows.h>

#include <iostream>

int main() {
  PDH_HQUERY cpuQuery;
  PDH_HCOUNTER cpuTotal;
  PDH_FMT_COUNTERVALUE counterVal;

  PdhOpenQuery(NULL, NULL, &cpuQuery);
  PdhAddCounter(cpuQuery, TEXT("\\Processor(_Total)\\% Processor Time"), NULL,
                &cpuTotal);
  PdhCollectQueryData(cpuQuery);

  while (true) {
    Sleep(1000);
    PdhCollectQueryData(cpuQuery);
    PdhGetFormattedCounterValue(cpuTotal, PDH_FMT_DOUBLE, NULL, &counterVal);
    std::cout << "CPU Usage: " << counterVal.doubleValue << "%" << std::endl;
  }

  PdhCloseQuery(cpuQuery);
  return 0;
}