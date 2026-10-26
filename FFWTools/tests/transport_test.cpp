#include "Transport.hpp"
#include <cstdlib>
#include <deque>
#include <iostream>
#include <stdexcept>

namespace {
constexpr std::uint64_t self = 76561198000000001ULL;
constexpr std::uint64_t peer = 76561198000000002ULL;
constexpr std::uint64_t stranger = 76561198000000003ULL;
int sendCalls, receiveCalls, released, closeCalls, sendResult = 1;
int observedFlags, observedChannel;
std::uint64_t observedPeer;
std::string observedPayload;
bool interfaceAvailable = true;
struct Message : SteamNetworkingMessage_t {
    std::string bytes;
    Message(std::uint64_t sender, std::string text, int channel = ffw::kChannel)
        : SteamNetworkingMessage_t{}, bytes(std::move(text)) {
        m_pData = bytes.data(); m_cbSize = static_cast<int>(bytes.size());
        m_nChannel = channel; m_identityPeer.SetSteamID64(sender);
    }
};
std::deque<Message*> incoming;
void check(bool test, const char* message) {
    if (!test) throw std::runtime_error(message);
}
void* interfacePointer() { return interfaceAvailable ? reinterpret_cast<void*>(1) : nullptr; }
std::uint64_t localId(void*) { return self; }
void setIdentity(SteamNetworkingIdentity* identity, std::uint64_t id) { identity->SetSteamID64(id); }
std::uint64_t getIdentity(const SteamNetworkingIdentity* identity) { return identity->GetSteamID64(); }
int send(void*, const SteamNetworkingIdentity* identity, const void* bytes, std::uint32_t size, int flags, int channel) {
    ++sendCalls; observedPeer = identity->GetSteamID64(); observedFlags = flags;
    observedChannel = channel; observedPayload.assign(static_cast<const char*>(bytes), size);
    return sendResult;
}
int receive(void*, int channel, SteamNetworkingMessage_t** out, int maximum) {
    ++receiveCalls; check(channel == ffw::kChannel && maximum == 1, "poll must only consume its own channel, one message at a time");
    if (incoming.empty()) return 0;
    *out = incoming.front(); incoming.pop_front(); return 1;
}
void release(SteamNetworkingMessage_t* message) { ++released; delete static_cast<Message*>(message); }
bool closeChannel(void*, const SteamNetworkingIdentity* identity, int channel) {
    ++closeCalls; check(identity->GetSteamID64() == peer && channel == ffw::kChannel, "close must affect only the selected peer's mod channel");
    return true;
}
ffw::SteamApi fakeApi() {
    return {interfacePointer, interfacePointer, localId, setIdentity, getIdentity, send, receive, release, closeChannel};
}
void run() {
    ffw::Transport transport(fakeApi());
    check(transport.localSteamId().value == "76561198000000001", "local Steam ID must remain an exact decimal string");
    check(!transport.send("76561198000000002", 0, "{}").empty() && sendCalls == 0, "wrong channel must not touch Steam");
    check(!transport.send("76561198000000002", ffw::kChannel, "").empty() && sendCalls == 0, "empty payload must be rejected");
    check(!transport.send("76561198000000002", ffw::kChannel, std::string(ffw::kMaxPayload + 1, 'x')).empty() && sendCalls == 0, "oversized payload must not reach Steam");
    for (const char* bad : {"", "0", "-1", "1", "76561198000000002x", " 76561198000000002", "18446744073709551616", "76561198000000001"}) {
        check(!transport.send(bad, ffw::kChannel, "{}").empty() && sendCalls == 0, "malformed or self peer must be rejected before send");
    }
    check(transport.send("76561198000000002", ffw::kChannel, "{\"kind\":\"hello\"}").empty(), "known peer's first hello must send");
    check(sendCalls == 1 && observedPeer == peer && observedChannel == ffw::kChannel && observedPayload == "{\"kind\":\"hello\"}", "transport must preserve peer, payload, and dedicated channel");
    check(observedFlags == (k_nSteamNetworkingSend_Reliable | k_nSteamNetworkingSend_AutoRestartBrokenSession), "reliable sends must reconnect after a broken Steam session");
    sendResult = 25;
    check(transport.send("76561198000000002", ffw::kChannel, "{}").find("25") != std::string::npos, "Steam error code must reach Lua, not report delivery");
    sendResult = 1;
    check(!transport.poll(0).error.empty() && receiveCalls == 0, "wrong receive channel must not drain game traffic");
    auto empty = transport.poll(ffw::kChannel);
    check(empty.senderId.empty() && empty.error.empty(), "empty queue is not a transport failure");
    incoming.push_back(new Message(peer, "{\"sequence\":2}"));
    auto packet = transport.poll(ffw::kChannel);
    check(packet.senderId == "76561198000000002" && packet.payload == "{\"sequence\":2}" && released == 1, "received packet must copy bytes, use authenticated Steam sender, and release message");
    incoming.push_back(new Message(stranger, "{}"));
    check(!transport.poll(ffw::kChannel).error.empty() && released == 2, "unintroduced sender must be rejected and released");
    incoming.push_back(new Message(peer, "{}", 0));
    check(!transport.poll(ffw::kChannel).error.empty() && released == 3, "misrouted receive must be rejected and released");
    incoming.push_back(new Message(peer, std::string(ffw::kMaxPayload + 1, 'x')));
    check(!transport.poll(ffw::kChannel).error.empty() && released == 4, "oversized receive must be rejected and released");
    auto* invalid = new Message(peer, "{}"); invalid->m_cbSize = -1; incoming.push_back(invalid);
    check(!transport.poll(ffw::kChannel).error.empty() && released == 5, "negative message size must be rejected and released");
    check(transport.close("76561198000000002").empty() && closeCalls == 1, "departed peer must close just the mod channel");
    incoming.push_back(new Message(peer, "{}"));
    check(!transport.poll(ffw::kChannel).error.empty() && released == 6, "departed peer must be removed from inbound allowlist");
    interfaceAvailable = false;
    check(!transport.localSteamId().error.empty(), "missing Steam user must return unavailable");
    check(!transport.send("76561198000000002", ffw::kChannel, "{}").empty(), "missing networking interface must return unavailable");
}
}
int main() {
    try { run(); std::cout << "PASS transport behavior (Steam boundary simulated; no multiplayer claim)\n"; }
    catch (const std::exception& error) { std::cerr << "FAIL " << error.what() << '\n'; return 1; }
}
