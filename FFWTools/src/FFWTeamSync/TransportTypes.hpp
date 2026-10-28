#pragma once
#include <cstdint>
#include <string>
namespace ffw {
inline constexpr int kChannel=0x464657;
inline constexpr std::size_t kMaxPayload=256*1024;
struct ValueResult {std::string value;std::string error;};
struct PollResult {std::string senderId;std::string payload;std::string error;};
}
