// Offline ABI probe: only loads steam_api64.dll into this helper process and
// calls pure identity and release helpers. Never initializes Steam or the game.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include "Transport.hpp"
#include <cstddef>
#include <iostream>

namespace {
int releases;
struct TestMessage : SteamNetworkingMessage_t { TestMessage() : SteamNetworkingMessage_t{} {} };
void releaseProbe(SteamNetworkingMessage_t*) { ++releases; }
}
int wmain(int argc, wchar_t** argv) {
    if (argc != 2) { std::cerr << "usage: transport_abi_test <absolute steam_api64.dll path>\n"; return 2; }
    std::string error;
    auto absent = ffw::bindLoadedSteam(error);
    if (absent.messages || error.empty()) { std::cerr << "FAIL absent DLL must report unavailable\n"; return 1; }
    const auto module = LoadLibraryExW(argv[1], nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!module) { std::cerr << "FAIL LoadLibraryEx " << GetLastError() << '\n'; return 1; }
    const auto api = ffw::bindLoadedSteam(error);
    if (!error.empty()) { std::cerr << "FAIL " << error << '\n'; return 1; }
    static_assert(sizeof(SteamNetworkingIdentity) == 136);
    static_assert(offsetof(SteamNetworkingMessage_t, m_identityPeer) == 16);
    static_assert(offsetof(SteamNetworkingMessage_t, m_pfnRelease) == 184);
    static_assert(offsetof(SteamNetworkingMessage_t, m_nChannel) == 192);
    SteamNetworkingIdentity identity{};
    api.setIdentity(&identity, 76561198000000002ULL);
    if (identity.m_eType != k_ESteamNetworkingIdentityType_SteamID || identity.GetSteamID64() != 76561198000000002ULL
        || api.getIdentity(&identity) != 76561198000000002ULL) {
        std::cerr << "FAIL identity ABI does not match the actual Steam DLL\n"; return 1;
    }
    TestMessage message;
    message.m_pfnRelease = releaseProbe;
    api.release(&message);
    if (releases != 1) { std::cerr << "FAIL release ABI does not match the actual Steam DLL\n"; return 1; }
    FreeLibrary(module);
    std::cout << "PASS actual Steam DLL exports and identity/release ABI; no networking or game initialization\n";
}
