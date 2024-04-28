#include "gpu.hpp"

#include "log.hpp"
#include "nvapi.h"

static bool nvapi_initialized = false;
static NvPhysicalGpuHandle hPhysicalGpu = nullptr;

// Initialize NVAPI and get GPU handle
void InitializeGPU() {
  NvAPI_Status status = NvAPI_Initialize();
  if (status == NVAPI_OK) {
    // Fetch the list of all GPUs
    NvPhysicalGpuHandle gpuHandles[NVAPI_MAX_PHYSICAL_GPUS];
    NvU32 gpuCount = 0;
    status = NvAPI_EnumPhysicalGPUs(gpuHandles, &gpuCount);
    if (status == NVAPI_OK && gpuCount > 0) {
      hPhysicalGpu = gpuHandles[0];  // Use the first GPU found
      nvapi_initialized = true;
      AppendToLogFile("NVAPI initialized successfully");
    } else {
      AppendToLogFile("Failed to enumerate GPUs: " + std::to_string(status));
    }
  } else {
    AppendToLogFile("Failed to initialize NVAPI: " + std::to_string(status));
  }
}

// Get GPU usage and temperature
void GetGPUUsageAndTemp(unsigned int &usage, unsigned int &temp) {
  if (!nvapi_initialized) {
    usage = 0;
    temp = 0;
    return;
  }

  // Get usage percentage
  NV_GPU_DYNAMIC_PSTATES_INFO_EX pStatesInfo;
  pStatesInfo.version = NV_GPU_DYNAMIC_PSTATES_INFO_EX_VER;
  NvAPI_Status get_usage_status = NvAPI_GPU_GetDynamicPstatesInfoEx(hPhysicalGpu, &pStatesInfo);
  if (get_usage_status != NVAPI_OK) {
    AppendToLogFile("Failed to get dynamic P-states info: " + std::to_string(get_usage_status));
    usage = 0;  // Default to 0 if failed
  } else {
    usage = pStatesInfo.utilization[0].percentage;  // Assuming index 0 is the GPU domain
  }

  // Get thermal settings for all sensors to diagnose the issue
  NV_GPU_THERMAL_SETTINGS pThermalSettings;
  pThermalSettings.version = NV_GPU_THERMAL_SETTINGS_VER;
  NvAPI_Status get_temp_status = NvAPI_GPU_GetThermalSettings(hPhysicalGpu, NVAPI_THERMAL_TARGET_ALL, &pThermalSettings);
  if (get_temp_status != NVAPI_OK) {
    AppendToLogFile("Failed to get thermal settings: " + std::to_string(get_temp_status));
    temp = 0;  // Default to 0 if failed
  } else {
    temp = (unsigned int)pThermalSettings.sensor[0].currentTemp;
  }
}

// Shutdown NVAPI
void ShutdownGPU() {
  if (nvapi_initialized) {
    NvAPI_Unload();
  }
}