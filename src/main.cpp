#include <windows.h>

#include <string>
#include <vector>

#include "log.hpp"
#include "cpu.hpp"
#include "gpu.hpp"

struct TextItem {
  std::string text;
  COLORREF color;  // RGB color
  int x, y;        // Position
};

std::vector<TextItem> textItems = {
    {"Text 1", RGB(255, 0, 0), 10, 10},
    {"Text 2", RGB(0, 255, 0), 10, 30},
    {"Text 3", RGB(0, 0, 255), 10, 50},
    // Add more text items as needed
};

static int count_thing = 0;
static double cpu_usage = 0;

LRESULT CALLBACK WindowProcedure(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
  switch (message) {
    case WM_TIMER: {
      // Example of how to change text color dynamically
      for (auto& item : textItems) {
        item.color = RGB(rand() % 256, rand() % 256, rand() % 256);  // Change to random color
      }
      HDC hdcScreen = GetDC(NULL);
      HDC hdc = CreateCompatibleDC(hdcScreen);
      HBITMAP hBmp = CreateCompatibleBitmap(hdcScreen, 300, 200);
      SelectObject(hdc, hBmp);

      // Set background to transparent
      BLENDFUNCTION blend = {};
      blend.BlendOp = AC_SRC_OVER;
      blend.SourceConstantAlpha = 255;
      blend.AlphaFormat = AC_SRC_ALPHA;

      RECT rect = {0, 0, 300, 200};                               // Define a RECT structure
      FillRect(hdc, &rect, (HBRUSH)GetStockObject(BLACK_BRUSH));  // Use it here

      unsigned int gpu_usage, gpu_temp, cpu_temp;
      double current_cpu_usage;
      GetGPUUsageAndTemp(gpu_usage, gpu_temp);
      GetCPUUsageAndTemp(current_cpu_usage, cpu_temp);

      if (current_cpu_usage > cpu_usage) {
        cpu_usage = current_cpu_usage;
      }

      count_thing++;
      if (count_thing == 50) {
        count_thing = 0;
        cpu_usage = 0;
      }

      std::string msg = "CPU: " + std::to_string(cpu_usage) + "%, " + std::to_string(cpu_temp) + "C " +
                        "GPU: " + std::to_string(gpu_usage) + "%, " + std::to_string(gpu_temp) + "C";

      for (const auto& item : textItems) {
        SetBkMode(hdc, TRANSPARENT);
        SetTextColor(hdc, item.color);
        TextOut(hdc, item.x, item.y, msg.c_str(), msg.size());
      }

      POINT ptZero = {0, 0};
      SIZE sizeWnd = {300, 200};
      UpdateLayeredWindow(hwnd, hdcScreen, NULL, &sizeWnd, hdc, &ptZero, 0, &blend, ULW_ALPHA);

      DeleteObject(hBmp);
      DeleteDC(hdc);
      ReleaseDC(NULL, hdcScreen);
      break;
    }
    case WM_DESTROY: {
      PostQuitMessage(0);
      break;
    }
    default:
      return DefWindowProc(hwnd, message, wParam, lParam);
  }
  return 0;
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
  AppendToLogFile("Hello World!");
  InitializeCPU();
  InitializeGPU();

  const char g_szClassName[] = "myWindowClass";

  WNDCLASSEX wc = {};
  wc.cbSize = sizeof(WNDCLASSEX);
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.lpfnWndProc = WindowProcedure;
  wc.cbClsExtra = 0;
  wc.cbWndExtra = 0;
  wc.hInstance = hInstance;
  wc.hCursor = LoadCursor(NULL, IDC_ARROW);
  wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
  wc.lpszClassName = g_szClassName;

  if (!RegisterClassEx(&wc)) {
    MessageBox(NULL, "Window Registration Failed!", "Error!", MB_ICONEXCLAMATION | MB_OK);
    return 0;
  }

  HWND hwnd = CreateWindowEx(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED,
      g_szClassName,
      "Taskbar Text",
      WS_POPUPWINDOW,
      0, 0, 300, 200,  // Adjust the size to fit all texts
      NULL,
      NULL,
      hInstance,
      NULL);

  if (hwnd == NULL) {
    MessageBox(NULL, "Window Creation Failed!", "Error!", MB_ICONEXCLAMATION | MB_OK);
    return 0;
  }

  SetTimer(hwnd, 1, 20, NULL);  // Set a timer to update every 20ms
  ShowWindow(hwnd, nCmdShow);
  UpdateWindow(hwnd);

  MSG Msg;
  while (GetMessage(&Msg, NULL, 0, 0) > 0) {
    TranslateMessage(&Msg);
    DispatchMessage(&Msg);
  }

  ShutdownGPU();
  ShutdownCPU();
  return Msg.wParam;
}
