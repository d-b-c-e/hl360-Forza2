// Qualification is Windows-only. Preserve the ordinary non-Windows path.
#include "provider_free.h"
namespace forza2::qualification {
bool Enabled(){return false;}
void Configure(rex::RuntimeConfig&){}
void PrivatePaths(rex::PathConfig&,const std::filesystem::path&){}
void Start(std::function<void()>){ }
void Stop(){}
void Frame(){}
bool Input(uint32_t,uint32_t,uint8_t*,uint32_t&){return false;}
bool Capabilities(uint32_t,uint32_t,uint8_t*,uint32_t&){return false;}
void NetworkCall(){}
void ForceCall(){}
}
