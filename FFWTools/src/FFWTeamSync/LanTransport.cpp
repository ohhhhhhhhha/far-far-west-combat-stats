#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <bcrypt.h>
#include "LanTransport.hpp"
#include <algorithm>
#include <array>
#include <charconv>
#include <deque>
#include <limits>
#include <map>
#include <mutex>
#include <vector>

namespace ffw { namespace {
constexpr std::size_t maxWire=kMaxPayload+512, maxQueue=2*1024*1024, maxInbox=4*1024*1024;
constexpr std::size_t maxConnections=8, maxPairs=15;
std::string hex(const unsigned char* p,std::size_t n){static constexpr char digits[]="0123456789abcdef";std::string r;r.reserve(n*2);for(std::size_t i=0;i<n;++i){r+=digits[p[i]>>4];r+=digits[p[i]&15];}return r;}
bool isHex(std::string_view s,std::size_t n){return s.size()==n&&std::all_of(s.begin(),s.end(),[](char c){return (c>='0'&&c<='9')||(c>='a'&&c<='f');});}
std::string randomHex(std::size_t n){std::vector<unsigned char> b(n);if(BCryptGenRandom(nullptr,b.data(),static_cast<ULONG>(n),BCRYPT_USE_SYSTEM_PREFERRED_RNG)<0)return {};return hex(b.data(),b.size());}
std::string mac(std::string_view key,std::string_view data){
    if(!isHex(key,64))return {};std::array<unsigned char,32> secret{};
    auto digit=[](char c){return c<='9'?c-'0':c-'a'+10;};
    for(std::size_t i=0;i<secret.size();++i)secret[i]=static_cast<unsigned char>((digit(key[i*2])<<4)|digit(key[i*2+1]));
    BCRYPT_ALG_HANDLE alg{};BCRYPT_HASH_HANDLE hash{};ULONG size{},written{};std::string result;
    if(BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,nullptr,BCRYPT_ALG_HANDLE_HMAC_FLAG)<0)return {};
    if(BCryptGetProperty(alg,BCRYPT_OBJECT_LENGTH,reinterpret_cast<PUCHAR>(&size),sizeof(size),&written,0)>=0){
        std::vector<unsigned char> object(size);std::array<unsigned char,32> digest{};
        if(BCryptCreateHash(alg,&hash,object.data(),size,secret.data(),static_cast<ULONG>(secret.size()),0)>=0){
            if(BCryptHashData(hash,reinterpret_cast<PUCHAR>(const_cast<char*>(data.data())),static_cast<ULONG>(data.size()),0)>=0&&BCryptFinishHash(hash,digest.data(),static_cast<ULONG>(digest.size()),0)>=0)result=hex(digest.data(),digest.size());
            BCryptDestroyHash(hash);
        }
    }
    BCryptCloseAlgorithmProvider(alg,0);SecureZeroMemory(secret.data(),secret.size());return result;
}
bool equalMac(std::string_view a,std::string_view b){if(a.size()!=64||b.size()!=64)return false;unsigned diff=0;for(std::size_t i=0;i<64;++i)diff|=static_cast<unsigned char>(a[i]^b[i]);return diff==0;}
bool number(std::string_view s,std::uint64_t& value){if(s.empty()||(s.size()>1&&s.front()=='0'))return false;auto [p,e]=std::from_chars(s.data(),s.data()+s.size(),value);return e==std::errc()&&p==s.data()+s.size();}
bool rawId(std::string_view s){std::uint64_t n{};return number(s,n)&&n<=2147483647;}
std::vector<std::string> split(std::string_view text,char delimiter){std::vector<std::string> parts;std::size_t start=0;for(;;){auto end=text.find(delimiter,start);parts.emplace_back(text.substr(start,end==std::string_view::npos?end:end-start));if(end==std::string_view::npos)return parts;start=end+1;}}
void closeSocket(SOCKET& s){if(s!=INVALID_SOCKET){closesocket(s);s=INVALID_SOCKET;}}
bool nonblocking(SOCKET s){u_long on=1;return ioctlsocket(s,FIONBIO,&on)==0;}
}
struct LanTransport::State {
    struct Connection {SOCKET socket=INVALID_SOCKET;bool connecting=false,authenticated=false;int phase=0;ULONGLONG started=0;std::string peer,key,clientNonce,serverNonce,context,input,output;std::size_t outputOffset=0;std::uint64_t tx=0,rx=0;};
    mutable std::mutex mutex;bool winsock=false,host=false;SOCKET listener=INVALID_SOCKET;int boundPort=0;
    std::string role,id,room,hostId,address,guestKey,lastError;ULONGLONG retryAt=0;
    std::map<std::string,std::string> pairs;std::vector<Connection> connections;std::deque<PollResult> inbox;std::size_t inboxBytes=0;
    State()=default;
    ~State(){release();}
    void release(){reset();if(winsock){WSACleanup();winsock=false;}}
    void reset(){for(auto& c:connections)closeSocket(c.socket);connections.clear();closeSocket(listener);pairs.clear();inbox.clear();inboxBytes=0;role.clear();id.clear();room.clear();hostId.clear();address.clear();guestKey.clear();lastError.clear();boundPort=0;retryAt=0;host=false;}
    bool peerInRoom(std::string_view peer)const{const std::string prefix="lan:"+room+":";return peer.starts_with(prefix)&&rawId(peer.substr(prefix.size()))&&peer!=id;}
    void forgetInbox(std::string_view peer){for(auto it=inbox.begin();it!=inbox.end();){if(it->senderId==peer){inboxBytes-=it->payload.size();it=inbox.erase(it);}else ++it;}}
    void drop(Connection& c,std::string_view why){closeSocket(c.socket);c.authenticated=false;lastError=why;c.output.clear();c.input.clear();
        // A socket failure has no authority to erase already authenticated inbox entries.
        // Explicit close/revoke/stop still clear admission and queued data.
    }
    bool queue(Connection& c,std::string_view body){if(body.empty()||body.size()>maxWire||c.output.size()-c.outputOffset+body.size()+4>maxQueue)return false;
        if(c.outputOffset){c.output.erase(0,c.outputOffset);c.outputOffset=0;}auto n=htonl(static_cast<u_long>(body.size()));c.output.append(reinterpret_cast<const char*>(&n),4);c.output.append(body);return true;}
    std::string contextFor(const Connection& c)const{const auto& guest=host?c.peer:id;return "FFWLAN1|"+room+"|"+hostId+"|"+guest+"|"+c.clientNonce+"|"+c.serverNonce;}
    bool connected(Connection& c){c.connecting=false;c.clientNonce=randomHex(16);if(c.clientNonce.empty())return false;c.phase=1;return queue(c,"C|"+id+"|"+c.clientNonce);}
    void connectGuest(ULONGLONG now){if(role!="guest"||!connections.empty()||now<retryAt)return;retryAt=now+1000;
        Connection c;c.socket=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);if(c.socket==INVALID_SOCKET){lastError="socket_failed";return;}
        if(!nonblocking(c.socket)){closeSocket(c.socket);lastError="nonblocking_failed";return;}
        BOOL noDelay=TRUE;setsockopt(c.socket,IPPROTO_TCP,TCP_NODELAY,reinterpret_cast<const char*>(&noDelay),sizeof(noDelay));
        sockaddr_in endpoint{};endpoint.sin_family=AF_INET;endpoint.sin_port=htons(static_cast<u_short>(boundPort));inet_pton(AF_INET,address.c_str(),&endpoint.sin_addr);
        c.peer=hostId;c.key=guestKey;c.started=now;int result=connect(c.socket,reinterpret_cast<sockaddr*>(&endpoint),sizeof(endpoint));
        if(result==0){if(!connected(c)){closeSocket(c.socket);lastError="crypto_failed";return;}}
        else if(WSAGetLastError()==WSAEWOULDBLOCK)c.connecting=true;
        else{closeSocket(c.socket);lastError="connect_failed";return;}
        connections.push_back(std::move(c));
    }
    bool frame(Connection& c,std::string_view body){
        if(body.size()<2||body[1]!='|')return false;
        if(!c.authenticated){auto f=split(body,'|');
            if(host&&c.phase==0&&f.size()==3&&f[0]=="C"&&peerInRoom(f[1])&&isHex(f[2],32)){
                auto found=pairs.find(f[1]);if(found==pairs.end())return false;
                c.peer=f[1];c.key=found->second;c.clientNonce=f[2];c.serverNonce=randomHex(16);if(c.serverNonce.empty())return false;c.context=contextFor(c);
                auto proof=mac(c.key,"host|"+c.context);if(proof.empty())return false;c.phase=1;return queue(c,"S|"+hostId+"|"+c.serverNonce+"|"+proof);
            }
            if(!host&&c.phase==1&&f.size()==4&&f[0]=="S"&&f[1]==hostId&&isHex(f[2],32)){
                c.serverNonce=f[2];c.context=contextFor(c);if(!equalMac(f[3],mac(c.key,"host|"+c.context)))return false;
                auto proof=mac(c.key,"guest|"+c.context);if(proof.empty()||!queue(c,"A|"+proof))return false;c.authenticated=true;c.phase=2;lastError.clear();return true;
            }
            if(host&&c.phase==1&&f.size()==2&&f[0]=="A"&&equalMac(f[1],mac(c.key,"guest|"+c.context))){
                // Replace only after the new socket proves the assigned peer key.
                for(auto& other:connections)if(&other!=&c&&other.peer==c.peer&&other.authenticated)drop(other,"reconnected");
                c.authenticated=true;c.phase=2;lastError.clear();return true;
            }
            return false;
        }
        if(body[0]!='D')return false;auto seqEnd=body.find('|',2);if(seqEnd==std::string_view::npos)return false;auto macEnd=body.find('|',seqEnd+1);if(macEnd==std::string_view::npos)return false;
        const auto sequence=body.substr(2,seqEnd-2),proof=body.substr(seqEnd+1,macEnd-seqEnd-1),payload=body.substr(macEnd+1);std::uint64_t n{};
        if(!number(sequence,n)||n!=c.rx+1||payload.empty()||payload.size()>kMaxPayload||payload.find('\0')!=std::string_view::npos)return false;
        if(!equalMac(proof,mac(c.key,c.context+"|data|"+c.peer+"|"+std::string(sequence)+"|"+std::string(payload))))return false;
        if(inbox.size()>=256||inboxBytes+payload.size()>maxInbox)return false;
        c.rx=n;inboxBytes+=payload.size();inbox.push_back({c.peer,std::string(payload),{}});return true;
    }
    void pump(){
        if(role.empty()||!winsock)return;auto now=GetTickCount64();
        if(host&&listener!=INVALID_SOCKET){for(std::size_t n=0;n<maxConnections;++n){SOCKET incoming=accept(listener,nullptr,nullptr);if(incoming==INVALID_SOCKET)break;
            if(connections.size()>=maxConnections||!nonblocking(incoming)){closesocket(incoming);continue;}
            BOOL noDelay=TRUE;setsockopt(incoming,IPPROTO_TCP,TCP_NODELAY,reinterpret_cast<const char*>(&noDelay),sizeof(noDelay));Connection c;c.socket=incoming;c.started=now;connections.push_back(std::move(c));}}
        connectGuest(now);
        for(auto& c:connections){if(c.socket==INVALID_SOCKET)continue;
            if(!c.authenticated&&now-c.started>10000){drop(c,"handshake_timeout");continue;}
            if(c.connecting){fd_set write,exception;FD_ZERO(&write);FD_ZERO(&exception);FD_SET(c.socket,&write);FD_SET(c.socket,&exception);timeval timeout{};
                int ready=select(0,nullptr,&write,&exception,&timeout);if(ready==SOCKET_ERROR){drop(c,"connect_failed");continue;}if(!ready)continue;
                int error=0,length=sizeof(error);if(getsockopt(c.socket,SOL_SOCKET,SO_ERROR,reinterpret_cast<char*>(&error),&length)!=0||error||!FD_ISSET(c.socket,&write)||!connected(c)){drop(c,"connect_failed");continue;}}
            // Bounded work per game tick; never sleep or wait for a peer.
            for(int budget=0;budget<16&&c.socket!=INVALID_SOCKET;++budget){char buffer[16384];int n=recv(c.socket,buffer,sizeof(buffer),0);
                if(n>0){c.input.append(buffer,n);if(c.input.size()>maxQueue){drop(c,"receive_overflow");break;}}
                else if(n==0){drop(c,"peer_disconnected");break;}
                else{if(WSAGetLastError()!=WSAEWOULDBLOCK)drop(c,"receive_failed");break;}}
            for(int n=0;n<32&&c.socket!=INVALID_SOCKET&&c.input.size()>=4;++n){u_long length{};memcpy(&length,c.input.data(),4);length=ntohl(length);
                if(!length||length>maxWire){drop(c,"invalid_frame");break;}if(c.input.size()<4+length)break;
                std::string body=c.input.substr(4,length);c.input.erase(0,4+length);if(!frame(c,body)){drop(c,"authentication_or_frame_failed");break;}}
            std::size_t budget=256*1024;
            while(c.socket!=INVALID_SOCKET&&c.outputOffset<c.output.size()&&budget){auto count=std::min({c.output.size()-c.outputOffset,budget,std::size_t(16384)});int n=::send(c.socket,c.output.data()+c.outputOffset,static_cast<int>(count),0);
                if(n>0){c.outputOffset+=n;budget-=n;}else{if(n==0||WSAGetLastError()!=WSAEWOULDBLOCK)drop(c,"send_failed");break;}}
            if(c.outputOffset==c.output.size()){c.output.clear();c.outputOffset=0;}
        }
        std::erase_if(connections,[](const Connection& c){return c.socket==INVALID_SOCKET;});
    }
};
LanTransport::LanTransport():state_(std::make_unique<State>()){}
LanTransport::~LanTransport()=default;
std::string LanTransport::configure(std::string_view role,std::string_view raw,std::string_view addr,int port,std::string_view token){
    std::lock_guard lock(state_->mutex);auto& s=*state_;
    if(role!="host"&&role!="guest")return "expected host or guest role";
    if(!rawId(raw))return "invalid replicated PlayerId";
    if(port<0||port>65535||(role=="guest"&&port==0))return "invalid TCP port";
    in_addr ipv4{};const std::string address(addr);if(inet_pton(AF_INET,address.c_str(),&ipv4)!=1||(role=="guest"&&ipv4.S_un.S_addr==INADDR_ANY))return "expected IPv4 address";
    std::vector<std::string> fields;
    if(role=="guest"){fields=split(token,'|');if(fields.size()!=5||fields[0]!="FFWLAN1"||!isHex(fields[1],32)||!rawId(fields[2])||fields[3]!=raw||fields[2]==raw||!isHex(fields[4],64))return "pairing code does not match this PlayerId";}
    // Explicit runtime entry only. Construction performs no Winsock calls.
    if(!s.winsock){WSADATA data{};if(WSAStartup(MAKEWORD(2,2),&data)!=0)return "WinSock initialization failed";s.winsock=true;}
    s.reset();s.role=role;s.host=role=="host";s.address=address;s.boundPort=port;
    s.room=s.host?randomHex(16):fields[1];if(s.room.empty()){s.release();return "random generator failed";}
    s.id="lan:"+s.room+":"+std::string(raw);s.hostId=s.host?s.id:"lan:"+s.room+":"+fields[2];
    if(s.host){
        s.listener=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);if(s.listener==INVALID_SOCKET){s.release();return "cannot create listener";}
        BOOL exclusive=TRUE;if(setsockopt(s.listener,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,reinterpret_cast<const char*>(&exclusive),sizeof(exclusive))!=0||!nonblocking(s.listener)){s.release();return "cannot configure listener";}
        sockaddr_in endpoint{};endpoint.sin_family=AF_INET;endpoint.sin_addr=ipv4;endpoint.sin_port=htons(static_cast<u_short>(port));
        if(bind(s.listener,reinterpret_cast<sockaddr*>(&endpoint),sizeof(endpoint))!=0||listen(s.listener,8)!=0){int code=WSAGetLastError();s.release();return "cannot listen (WinSock "+std::to_string(code)+")";}
        int len=sizeof(endpoint);if(getsockname(s.listener,reinterpret_cast<sockaddr*>(&endpoint),&len)!=0){s.release();return "cannot read listener address";}s.boundPort=ntohs(endpoint.sin_port);
    }else s.guestKey=fields[4];
    s.pump();return {};
}
ValueResult LanTransport::pair(std::string_view peer){std::lock_guard lock(state_->mutex);auto& s=*state_;
    if(!s.host||s.role.empty()||!s.peerInRoom(peer))return {{},"peer is not a different player in this LAN room"};
    auto p=std::string(peer);if(!s.pairs.contains(p)){if(s.pairs.size()>=maxPairs)return {{},"pairing capacity reached"};auto key=randomHex(32);if(key.empty())return {{},"random generator failed"};s.pairs.emplace(p,std::move(key));}
    return {"FFWLAN1|"+s.room+"|"+s.id.substr(s.id.rfind(':')+1)+"|"+p.substr(p.rfind(':')+1)+"|"+s.pairs[p],{}};
}
ValueResult LanTransport::localPlayerId(){std::lock_guard lock(state_->mutex);return state_->id.empty()?ValueResult{{},"LAN room not configured"}:ValueResult{state_->id,{}};}
ValueResult LanTransport::status(){std::lock_guard lock(state_->mutex);auto& s=*state_;if(s.role.empty())return {"off",{}};std::size_t ready=0;for(auto& c:s.connections)if(c.authenticated)++ready;
    return {std::string(ready?"connected:":s.host?"listening:":"connecting:")+std::to_string(ready)+";port="+std::to_string(s.boundPort)+";paired="+std::to_string(s.pairs.size())+(s.lastError.empty()?"":";last="+s.lastError),{}};}
std::string LanTransport::send(std::string_view peer,std::int64_t channel,std::string_view payload){std::lock_guard lock(state_->mutex);auto& s=*state_;
    if(channel!=kChannel)return "unexpected mod channel";if(payload.empty()||payload.size()>kMaxPayload||payload.find('\0')!=std::string_view::npos)return "invalid payload";
    if(!s.peerInRoom(peer)||(!s.host&&peer!=s.hostId)||(s.host&&!s.pairs.contains(std::string(peer))))return "peer is not paired";
    s.pump();for(auto& c:s.connections)if(c.authenticated&&c.peer==peer){if(c.tx==std::numeric_limits<std::uint64_t>::max())return "connection sequence exhausted";auto sequence=std::to_string(c.tx+1);
        auto proof=mac(c.key,c.context+"|data|"+s.id+"|"+sequence+"|"+std::string(payload));if(proof.empty())return "authentication failed";
        if(!s.queue(c,"D|"+sequence+"|"+proof+"|"+std::string(payload)))return "send queue full";++c.tx;return {};}
    return "peer not connected";
}
PollResult LanTransport::poll(std::int64_t channel){std::lock_guard lock(state_->mutex);if(channel!=kChannel)return {{},{},"unexpected mod channel"};state_->pump();if(state_->inbox.empty())return {};auto r=std::move(state_->inbox.front());state_->inbox.pop_front();state_->inboxBytes-=r.payload.size();return r;}
std::string LanTransport::close(std::string_view peer){std::lock_guard lock(state_->mutex);for(auto& c:state_->connections)if(c.peer==peer)state_->drop(c,"connection_closed");state_->forgetInbox(peer);return {};}
std::string LanTransport::revoke(std::string_view peer){std::lock_guard lock(state_->mutex);auto& s=*state_;if(!s.host&&peer==s.hostId){s.release();return {};}s.pairs.erase(std::string(peer));for(auto& c:s.connections)if(c.peer==peer)s.drop(c,"pairing_revoked");s.forgetInbox(peer);return {};}
void LanTransport::update(){std::lock_guard lock(state_->mutex);state_->pump();}
void LanTransport::stop(){std::lock_guard lock(state_->mutex);state_->release();}
int LanTransport::port()const{std::lock_guard lock(state_->mutex);return state_->boundPort;}
}
