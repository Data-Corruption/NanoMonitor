#pragma once

#include <pdh.h>
#include <pdhmsg.h>
#include <windows.h>

#include "log.hpp"

static bool PDH_initialized = false;

static PDH_HQUERY cpuQuery;
static PDH_HCOUNTER cpuTotal;
static PDH_FMT_COUNTERVALUE counterVal;

void initPDH() {
  if (PdhOpenQuery(NULL, NULL, &cpuQuery) != ERROR_SUCCESS) {
    AppendToLogFile("PDH failed to open query");
    return;
  }
  if (PdhAddCounter(cpuQuery, TEXT("\\Processor(_Total)\\% Processor Time"), NULL, &cpuTotal) != ERROR_SUCCESS) {
    AppendToLogFile("PDH failed to add counter");
    return;
  }
  if (PdhCollectQueryData(cpuQuery) != ERROR_SUCCESS) {
    AppendToLogFile("PDH failed to collect query data");
    return;
  }
  AppendToLogFile("PDH initialized successfully");
  PDH_initialized = true;
}

void InitializeCPU() {
  initPDH();
}

void GetCPUUsageAndTemp(double& usage, unsigned int& temp) {
  usage = 0;
  temp = 0;

  // Get usage
  if (PDH_initialized) {
    PDH_STATUS status = PdhCollectQueryData(cpuQuery);
    if (status != ERROR_SUCCESS) {
      AppendToLogFile("PDH failed to collect query data, status: " + std::to_string(status));
      usage = 0;
    } else {
      status = PdhGetFormattedCounterValue(cpuTotal, PDH_FMT_DOUBLE, NULL, &counterVal);
      if (status != ERROR_SUCCESS) {
        AppendToLogFile("PDH failed to get formatted counter value, status: " + std::to_string(status));
        usage = 0;
      } else {
        usage = counterVal.doubleValue;
      }
    }
  }

  // Get temperature: wip
}

void ShutdownCPU() {
  if (PDH_initialized) {
    PdhCloseQuery(cpuQuery);
  }
}