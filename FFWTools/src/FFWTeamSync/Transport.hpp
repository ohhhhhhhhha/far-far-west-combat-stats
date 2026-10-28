#pragma once

#include <cstdint>
#include <mutex>
#include <set>
#include <string>
#include <string_view>
#include <steamnetworkingtypes.h>
#include "TransportTypes.hpp"

namespace ffw {

// Only the flat ABI exported by the game's already-loaded steam_api64.dll.
// There is no Steam initialization, callback pump, or owned Steam connection.
struct SteamApi {
    void* (*messages)(){};
    void* (*user)(){};
    std::uint64_t (*getSteamId)(void*){};
    void (*setIdentity)(SteamNetworkingIdentity*, std::uint64_t){};
    std::uint64_t (*getIdentity)(const SteamNetworkingIdentity*){};
    int (*send)(void*, const SteamNetworkingIdentity*, const void*, std::uint32_t, int, int){};
    int (*receive)(void*, int, SteamNetworkingMessage_t**, int){};
    void (*release)(SteamNetworkingMessage_t*){};
    bool (*closeChannel)(void*, const SteamNetworkingIdentity*, int){};
};

SteamApi bindLoadedSteam(std::string& error);


class Transport {
public:
    explicit Transport(SteamApi api = {}) : api_(api) {}
    ValueResult localSteamId();
    std::string send(std::string_view peer, std::int64_t channel, std::string_view payload);
    PollResult poll(std::int64_t channel);
    std::string close(std::string_view peer);

private:
    bool ready(std::string& error);
    SteamApi api_;
    std::mutex mutex_;
    std::set<std::uint64_t> peers_;
};
}
