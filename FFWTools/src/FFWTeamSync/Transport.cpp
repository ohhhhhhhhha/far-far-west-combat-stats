#include "Transport.hpp"
#include <charconv>
#include <memory>

namespace ffw {
namespace {
bool parsePeer(std::string_view text, std::uint64_t& id) {
    if (text.empty() || text.front() == '0') return false;
    const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), id);
    if (error != std::errc{} || end != text.data() + text.size()) return false;
    const CSteamID steamId(id);
    return steamId.IsValid() && steamId.GetEUniverse() == k_EUniversePublic
        && steamId.GetEAccountType() == k_EAccountTypeIndividual;
}
}

bool Transport::ready(std::string& error) {
    if (!api_.messages) api_ = bindLoadedSteam(error);
    if (!api_.messages || !api_.user || !api_.getSteamId || !api_.setIdentity || !api_.getIdentity
        || !api_.send || !api_.receive || !api_.release || !api_.closeChannel) {
        if (error.empty()) error = "Steam flat API unavailable";
        return false;
    }
    return true;
}

ValueResult Transport::localSteamId() {
    std::lock_guard lock(mutex_);
    ValueResult result;
    if (!ready(result.error)) return result;
    auto* user = api_.user();
    if (!user) { result.error = "Steam user unavailable"; return result; }
    const auto id = api_.getSteamId(user);
    std::uint64_t parsed{};
    result.value = std::to_string(id);
    if (!parsePeer(result.value, parsed)) { result.value.clear(); result.error = "Steam user ID unavailable"; }
    return result;
}

std::string Transport::send(std::string_view peer, std::int64_t channel, std::string_view payload) {
    std::lock_guard lock(mutex_);
    if (channel != kChannel) return "unsupported channel";
    if (payload.empty() || payload.size() > kMaxPayload) return "payload size out of range";
    std::uint64_t id{};
    if (!parsePeer(peer, id)) return "invalid Steam peer ID";
    std::string error;
    if (!ready(error)) return error;
    auto* user = api_.user();
    auto* messages = api_.messages();
    if (!user || !messages) return "Steam interface unavailable";
    if (id == api_.getSteamId(user)) return "cannot send to self";
    SteamNetworkingIdentity remote{};
    api_.setIdentity(&remote, id);
    // Sending also accepts a pending incoming session. Every team member sends a
    // hello to discovered peers; this avoids taking over the game's callback pump.
    const int result = api_.send(messages, &remote, payload.data(), static_cast<std::uint32_t>(payload.size()),
        k_nSteamNetworkingSend_Reliable | k_nSteamNetworkingSend_AutoRestartBrokenSession, kChannel);
    if (result != k_EResultOK) return "Steam send result " + std::to_string(result);
    peers_.insert(id);
    return {};
}

PollResult Transport::poll(std::int64_t channel) {
    std::lock_guard lock(mutex_);
    PollResult result;
    if (channel != kChannel) { result.error = "unsupported channel"; return result; }
    if (!ready(result.error)) return result;
    auto* messages = api_.messages();
    if (!messages) { result.error = "Steam networking messages unavailable"; return result; }
    SteamNetworkingMessage_t* raw{};
    const int count = api_.receive(messages, kChannel, &raw, 1);
    if (count == 0) return result;
    if (count != 1 || !raw) { result.error = "Steam receive result " + std::to_string(count); return result; }
    const std::unique_ptr<SteamNetworkingMessage_t, decltype(api_.release)> message(raw, api_.release);
    if (message->m_nChannel != kChannel) { result.error = "received wrong channel"; return result; }
    if (message->m_cbSize <= 0 || static_cast<std::size_t>(message->m_cbSize) > kMaxPayload || !message->m_pData) {
        result.error = "received payload size out of range"; return result;
    }
    const auto sender = api_.getIdentity(&message->m_identityPeer);
    if (!peers_.contains(sender)) { result.error = "sender is not an introduced peer"; return result; }
    result.senderId = std::to_string(sender);
    result.payload.assign(static_cast<const char*>(message->m_pData), static_cast<std::size_t>(message->m_cbSize));
    return result;
}

std::string Transport::close(std::string_view peer) {
    std::lock_guard lock(mutex_);
    std::uint64_t id{};
    if (!parsePeer(peer, id)) return "invalid Steam peer ID";
    if (peers_.erase(id) == 0) return {};
    std::string error;
    if (!ready(error)) return error;
    auto* messages = api_.messages();
    if (!messages) return "Steam networking messages unavailable";
    SteamNetworkingIdentity remote{};
    api_.setIdentity(&remote, id);
    // Sessions may also carry the game's own traffic. Never close the session.
    api_.closeChannel(messages, &remote, kChannel);
    return {};
}
}
