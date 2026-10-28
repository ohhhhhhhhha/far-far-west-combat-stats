#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <atomic>
#include "LanTransport.hpp"
#include <string>
namespace {thread_local std::string result;const char* value(ffw::ValueResult r){result=r.error.empty()?r.value:"!"+r.error;return result.c_str();}const char* error(std::string e){result=e.empty()?"":"!"+e;return result.c_str();}}
extern "C" {
__declspec(dllexport) void* lan_create(){return new ffw::LanTransport();}
__declspec(dllexport) void lan_destroy(void* p){delete static_cast<ffw::LanTransport*>(p);}
__declspec(dllexport) const char* lan_configure(void*p,const char*role,const char*id,const char*address,int port,const char*token){return error(static_cast<ffw::LanTransport*>(p)->configure(role,id,address,port,token));}
__declspec(dllexport) const char* lan_pair(void*p,const char*peer){return value(static_cast<ffw::LanTransport*>(p)->pair(peer));}
__declspec(dllexport) const char* lan_id(void*p){return value(static_cast<ffw::LanTransport*>(p)->localPlayerId());}
__declspec(dllexport) const char* lan_status(void*p){return value(static_cast<ffw::LanTransport*>(p)->status());}
__declspec(dllexport) int lan_port(void*p){return static_cast<ffw::LanTransport*>(p)->port();}
__declspec(dllexport) const char* lan_send(void*p,const char*peer,int channel,const char*body){return error(static_cast<ffw::LanTransport*>(p)->send(peer,channel,body));}
__declspec(dllexport) const char* lan_poll(void*p,int channel){auto r=static_cast<ffw::LanTransport*>(p)->poll(channel);result=!r.error.empty()?"!"+r.error:r.senderId.empty()?"":r.senderId+"\n"+r.payload;return result.c_str();}
__declspec(dllexport) const char* lan_close(void*p,const char*peer){return error(static_cast<ffw::LanTransport*>(p)->close(peer));}
__declspec(dllexport) const char* lan_revoke(void*p,const char*peer){return error(static_cast<ffw::LanTransport*>(p)->revoke(peer));}
__declspec(dllexport) void lan_update(void*p){static_cast<ffw::LanTransport*>(p)->update();}
__declspec(dllexport) void lan_stop(void*p){static_cast<ffw::LanTransport*>(p)->stop();}
}

namespace {std::atomic<int> startupCalls{},cleanupCalls{};}
int WSAAPI ffw_record_startup(WORD version,LPWSADATA data){++startupCalls;return WSAStartup(version,data);}
int WSAAPI ffw_record_cleanup(){++cleanupCalls;return WSACleanup();}
extern "C" __declspec(dllexport) int lan_startup_count(){return startupCalls.load();}
extern "C" __declspec(dllexport) int lan_cleanup_count(){return cleanupCalls.load();}
