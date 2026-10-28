#include <Mod/CppUserModBase.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include "Transport.hpp"
#include "LanTransport.hpp"

namespace {
using Lua = RC::LuaMadeSimple::Lua;
ffw::Transport transport;
// Non-owning facade pointer: no global LAN constructor/destructor under loader lock.
ffw::LanTransport* lan=nullptr;

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


int lanConfigure(const Lua& lua) {
    if(!lan)return valueError(lua,"LAN bridge is unavailable");
    if(lua.get_stack_size()!=5||!lua.is_string(1)||!lua.is_string(2)||!lua.is_string(3)||!lua.is_integer(4)||!lua.is_string(5))
        return valueError(lua,"expected role, replicated PlayerId, IPv4 address, port, pairing code");
    const std::string role(lua.get_string(1)),id(lua.get_string(1)),address(lua.get_string(1));
    const auto port=lua.get_integer(1);const std::string token(lua.get_string(1));
    if(port<0||port>65535)return valueError(lua,"invalid TCP port");
    const auto error=lan->configure(role,id,address,static_cast<int>(port),token);
    if(!error.empty())return valueError(lua,error);lua.set_bool(true);return 1;
}
int lanPair(const Lua& lua) {
    if(!lan)return valueError(lua,"LAN bridge is unavailable");
    if(lua.get_stack_size()!=1||!lua.is_string(1))return valueError(lua,"expected roster player ID");
    const std::string peer(lua.get_string(1));const auto r=lan->pair(peer);
    if(!r.error.empty())return valueError(lua,r.error);lua.set_string(r.value);return 1;
}
int lanId(const Lua& lua) {
    if(!lan)return valueError(lua,"LAN bridge is unavailable");const auto r=lan->localPlayerId();if(!r.error.empty())return valueError(lua,r.error);lua.set_string(r.value);return 1;}
int lanStatus(const Lua& lua) {
    if(!lan)return valueError(lua,"LAN bridge is unavailable");const auto r=lan->status();if(!r.error.empty())return valueError(lua,r.error);lua.set_string(r.value);return 1;}
int lanUpdate(const Lua& lua) {
    if(!lan)return valueError(lua,"LAN bridge is unavailable");lan->update();lua.set_bool(true);return 1;}
int lanStop(const Lua& lua) {
    if(!lan)return valueError(lua,"LAN bridge is unavailable");lan->stop();lua.set_bool(true);return 1;}
int lanSend(const Lua& lua) {
    if(!lan)return valueError(lua,"LAN bridge is unavailable");
    if(lua.get_stack_size()!=3||!lua.is_string(1)||!lua.is_integer(2)||!lua.is_string(3))return valueError(lua,"expected peer ID, channel and JSON");
    const std::string peer(lua.get_string(1));const auto channel=lua.get_integer(1);const std::string payload(lua.get_string(1));
    const auto error=lan->send(peer,channel,payload);if(!error.empty())return valueError(lua,error);lua.set_bool(true);return 1;
}
int lanPoll(const Lua& lua) {
    if(!lan)return pollError(lua,"LAN bridge is unavailable");
    if(lua.get_stack_size()!=1||!lua.is_integer(1))return pollError(lua,"expected integer channel");
    const auto r=lan->poll(lua.get_integer(1));if(!r.error.empty())return pollError(lua,r.error);
    if(r.senderId.empty()){lua.set_nil();lua.set_nil();return 2;}lua.set_string(r.senderId);lua.set_string(r.payload);return 2;
}
int lanClose(const Lua& lua) {
    if(!lan)return valueError(lua,"LAN bridge is unavailable");
    if(lua.get_stack_size()!=1||!lua.is_string(1))return valueError(lua,"expected peer ID");
    const std::string peer(lua.get_string(1));const auto error=lan->close(peer);if(!error.empty())return valueError(lua,error);lua.set_bool(true);return 1;
}
int lanRevoke(const Lua& lua) {
    if(!lan)return valueError(lua,"LAN bridge is unavailable");
    if(lua.get_stack_size()!=1||!lua.is_string(1))return valueError(lua,"expected peer ID");
    const std::string peer(lua.get_string(1));const auto error=lan->revoke(peer);if(!error.empty())return valueError(lua,error);lua.set_bool(true);return 1;
}

void installApi(const Lua& lua) {
    lua.register_function("FFWTeamSync_lanConfigure",lanConfigure);
    lua.register_function("FFWTeamSync_lanPair",lanPair);
    lua.register_function("FFWTeamSync_lanId",lanId);
    lua.register_function("FFWTeamSync_lanStatus",lanStatus);
    lua.register_function("FFWTeamSync_lanUpdate",lanUpdate);
    lua.register_function("FFWTeamSync_lanStop",lanStop);
    lua.register_function("FFWTeamSync_lanSend",lanSend);
    lua.register_function("FFWTeamSync_lanPoll",lanPoll);
    lua.register_function("FFWTeamSync_lanClose",lanClose);
    lua.register_function("FFWTeamSync_lanRevoke",lanRevoke);
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
FFWTeamSync.lan = {
    apiVersion=1,channel=4605527,maxPayload=262144,
    configure=FFWTeamSync_lanConfigure,pair=FFWTeamSync_lanPair,
    localPlayerId=FFWTeamSync_lanId,status=FFWTeamSync_lanStatus,
    update=FFWTeamSync_lanUpdate,stop=FFWTeamSync_lanStop,
    poll=FFWTeamSync_lanPoll,close=FFWTeamSync_lanClose,revoke=FFWTeamSync_lanRevoke,
    send=function(peer,channel,payload)
        if type(payload)~="string" or payload:find("\0",1,true) then return nil,"expected JSON text without embedded NUL" end
        return FFWTeamSync_lanSend(peer,channel,payload)
    end
}
)lua");
}

class FFWTeamSyncMod final : public RC::CppUserModBase {
    // Owned by start_mod/uninstall_mod runtime lifetime, never a DLL global.
    ffw::LanTransport lan_;
public:
    ~FFWTeamSyncMod() override { lan=nullptr; }
    FFWTeamSyncMod() {
        lan=&lan_;
        ModName = STR("FFWTeamSync");
        ModVersion = STR("0.2.0-beta.1");
        ModDescription = STR("Steam and paired LAN messages bridge for FFWStats");
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
