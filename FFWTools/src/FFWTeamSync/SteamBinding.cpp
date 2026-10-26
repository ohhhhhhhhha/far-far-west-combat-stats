#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <bit>
#include "Transport.hpp"

namespace ffw {
SteamApi bindLoadedSteam(std::string& error) {
    SteamApi api;
    // The game owns Steam. Loading a second library or initializing/shutting it
    // down here could alter the game's session, so only bind an existing module.
    const auto module = GetModuleHandleW(L"steam_api64.dll");
    if (!module) { error = "steam_api64.dll is not loaded"; return {}; }
#define FFW_BIND(member, symbol) \
    api.member = std::bit_cast<decltype(api.member)>(GetProcAddress(module, symbol)); \
    if (!api.member) { error = "missing Steam export: " symbol; return {}; }
    FFW_BIND(messages, "SteamAPI_SteamNetworkingMessages_SteamAPI_v002")
    FFW_BIND(user, "SteamAPI_SteamUser_v021")
    FFW_BIND(getSteamId, "SteamAPI_ISteamUser_GetSteamID")
    FFW_BIND(setIdentity, "SteamAPI_SteamNetworkingIdentity_SetSteamID64")
    FFW_BIND(getIdentity, "SteamAPI_SteamNetworkingIdentity_GetSteamID64")
    FFW_BIND(send, "SteamAPI_ISteamNetworkingMessages_SendMessageToUser")
    FFW_BIND(receive, "SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel")
    FFW_BIND(release, "SteamAPI_SteamNetworkingMessage_t_Release")
    FFW_BIND(closeChannel, "SteamAPI_ISteamNetworkingMessages_CloseChannelWithUser")
#undef FFW_BIND
    error.clear();
    return api;
}
}
