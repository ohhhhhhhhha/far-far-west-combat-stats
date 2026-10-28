#pragma once
#include "TransportTypes.hpp"
#include <string_view>
#include <memory>
namespace ffw {
class LanTransport {
public:
    LanTransport();~LanTransport();
    LanTransport(const LanTransport&)=delete;LanTransport& operator=(const LanTransport&)=delete;
    std::string configure(std::string_view role,std::string_view rawId,std::string_view address,int port,std::string_view token);
    ValueResult pair(std::string_view peer);ValueResult localPlayerId();ValueResult status();
    std::string send(std::string_view peer,std::int64_t channel,std::string_view payload);
    PollResult poll(std::int64_t channel);
    std::string close(std::string_view peer);std::string revoke(std::string_view peer);
    void update();void stop();int port() const;
private:struct State;std::unique_ptr<State> state_;
};
}
