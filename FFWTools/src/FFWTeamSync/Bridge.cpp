#include <Mod/CppUserModBase.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include "Transport.hpp"

namespace {
using Lua = RC::LuaMadeSimple::Lua;
ffw::Transport transport;

int valueError(const Lua& lua, std::string_view error) {
    lua.set_nil(); lua.set_string(error); return 2;
}
int pollError(const Lua& lua, std::string_view error) {
    lua.set_nil(); lua.set_nil(); lua.set_string(error); return 3;
}
int localSteamId(const Lua& lua) {
    const auto result = transport.localSteamId();
    if (!result.error.empty()) return valueError(lua, result.error);
    lua.set_string(result.value); return 1;
}
int send(const Lua& lua) {
    if (lua.get_stack_size() != 3 || !lua.is_string(1) || !lua.is_integer(2) || !lua.is_string(3))
        return valueError(lua, "expected Steam ID string, integer channel, JSON string");
    // LuaMadeSimple getters consume the argument. Copy each string before the
    // next Lua operation; do not retain a view of Lua-owned memory.
    const std::string peer(lua.get_string(1));
    const auto channel = lua.get_integer(1);
    const std::string payload(lua.get_string(1));
    const auto error = transport.send(peer, channel, payload);
    if (!error.empty()) return valueError(lua, error);
    lua.set_bool(true); return 1;
}
int poll(const Lua& lua) {
    if (lua.get_stack_size() != 1 || !lua.is_integer(1)) return pollError(lua, "expected integer channel");
    const auto result = transport.poll(lua.get_integer(1));
    if (!result.error.empty()) return pollError(lua, result.error);
    if (result.senderId.empty()) { lua.set_nil(); lua.set_nil(); return 2; }
    lua.set_string(result.senderId); lua.set_string(result.payload); return 2;
}
int close(const Lua& lua) {
    if (lua.get_stack_size() != 1 || !lua.is_string(1)) return valueError(lua, "expected Steam ID string");
    const std::string peer(lua.get_string(1));
    const auto error = transport.close(peer);
    if (!error.empty()) return valueError(lua, error);
    lua.set_bool(true); return 1;
}

void installApi(const Lua& lua) {
    lua.register_function("FFWTeamSync_localSteamId", localSteamId);
    lua.register_function("FFWTeamSync_send", send);
    lua.register_function("FFWTeamSync_poll", poll);
    lua.register_function("FFWTeamSync_close", close);
    // Use the exported wrapper to build the facade, avoiding direct calls into
    // the statically linked Lua runtime. JSON text never needs embedded NULs.
    lua.execute_string(R"lua(
FFWTeamSync = {
    apiVersion = 1,
    channel = 4605527,
    maxPayload = 262144,
    localSteamId = FFWTeamSync_localSteamId,
    poll = FFWTeamSync_poll,
    close = FFWTeamSync_close,
    send = function(peer, channel, payload)
        if type(payload) ~= "string" or payload:find("\0", 1, true) then
            return nil, "expected JSON text without embedded NUL"
        end
        return FFWTeamSync_send(peer, channel, payload)
    end
}
)lua");
}

class FFWTeamSyncMod final : public RC::CppUserModBase {
public:
    FFWTeamSyncMod() {
        ModName = STR("FFWTeamSync");
        ModVersion = STR("0.1.0");
        ModDescription = STR("Steam messages bridge for FFWStats; multiplayer validation pending");
        ModAuthors = STR("Local FFWTools project");
        ModIntendedSDKVersion = STR("3.0.1-1181-g83330635");
        register_on_lua_start([](RC::CppUserModBase*, RC::CStringView name, Lua& lua, Lua&, Lua&, Lua*) {
            const RC::StringViewType modName(name.data, name.size);
            // UE4SS fires this before executing the Lua mod's main.lua. The
            // main, async, and hook coroutines share this Lua global environment.
            if (modName == STR("FFWStats") || modName == STR("FFWTeamSyncSmoke") || modName == STR("FFWProbe")) installApi(lua);
        });
    }
};
}

extern "C" __declspec(dllexport) RC::CppUserModBase* start_mod() { return new FFWTeamSyncMod(); }
extern "C" __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
