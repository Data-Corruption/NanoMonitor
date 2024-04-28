#pragma once

void InitializeGPU();
void GetGPUUsageAndTemp(unsigned int& usage, unsigned int& temp);
void ShutdownGPU();