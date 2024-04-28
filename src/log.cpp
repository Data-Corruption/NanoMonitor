#include "log.hpp"

#include <fstream>
#include <string>

// Appends a message to the log file.
void AppendToLogFile(const std::string &msg) {
  std::ofstream file(LOG_PATH, std::ios::binary | std::ios::app);
  file << msg + "\n";
}