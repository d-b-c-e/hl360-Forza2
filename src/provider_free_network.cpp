#include "provider_free.h"
#include <cstring>
#include <atomic>
#include <stdexcept>
#include <utility>
#include <vector>
#include <windows.h>
#include <rex/ppc/context.h>

namespace {
using GuestFunction = void (*)(PPCContext&, uint8_t*);
using SdkRegistry=std::vector<std::pair<const char*,GuestFunction>>;
std::atomic<uint64_t> registry_entries{0};
SdkRegistry* RuntimeRegistry(){
  // Exact data export from the pinned0.10.0 rexruntime.dll/E359209F tuple.
  // Bind the DLL's real vector, not the executable's inline-header copy.
  constexpr char symbol[]="?registry@?1??GetPPCFuncRegistry@ppc@rex@@YAAEAV?$vector@U?$pair@PEBDP6AXAEAUPPCContext@@PEAE@Z@std@@V?$allocator@U?$pair@PEBDP6AXAEAUPPCContext@@PEAE@Z@std@@@2@@std@@XZ@4V45@A";
  auto* registry=reinterpret_cast<SdkRegistry*>(GetProcAddress(GetModuleHandleW(L"rexruntime.dll"),symbol));
  if(!registry||registry->size()<40||registry->size()>16384)throw std::runtime_error("Pinned SDK dynamic registry unavailable");
  return registry;
}
void DenyDynamicNetwork(PPCContext& ctx,uint8_t*){forza2::qualification::NetworkCall();ctx.r3.u64=0xffffffff;}
void Forward(const char* name, PPCContext& ctx, uint8_t* base) {
  auto function = reinterpret_cast<GuestFunction>(GetProcAddress(GetModuleHandleW(L"rexruntime.dll"),name));
  if (function) function(ctx,base); else ctx.r3.u64 = 1167;
}
void OfflineAddress(const char* name,PPCContext& ctx,uint8_t* base) {
  if (std::strcmp(name,"NetDll_XNetGetTitleXnAddr")==0 && ctx.r4.u32>=0x1000 &&
      uint64_t(ctx.r4.u32)+36<=0x100000000ull) std::memset(base+ctx.r4.u32,0,36);
}
}
#define FM2_NET(name,result) \
extern "C" void __imp__##name(PPCContext& __restrict ctx,uint8_t* base) { \
  if (!forza2::qualification::Enabled()) {Forward("__imp__" #name,ctx,base);return;} \
  forza2::qualification::NetworkCall(); \
  OfflineAddress(#name,ctx,base); \
  ctx.r3.u64 = result; \
}
#include "provider_free_network.def"
#undef FM2_NET

namespace {
struct NetworkOverride{const char* name;GuestFunction function;};
NetworkOverride known_network[]={
#define FM2_NET(name,result) {"__imp__" #name,&__imp__##name},
#include "provider_free_network.def"
#undef FM2_NET
};
GuestFunction FencedNetworkFunction(const char* name){
  for(const auto& entry:known_network)if(std::strcmp(entry.name,name)==0)return entry.function;
  return &DenyDynamicNetwork;
}
}
namespace forza2::qualification {
uint64_t ArmNetworkRegistry(){
  if(!Enabled())return 0;
  auto* registry=RuntimeRegistry();uint64_t count=0;
  for(auto& entry:*registry){
    if(entry.first&&std::strncmp(entry.first,"__imp__NetDll_",14)==0){entry.second=FencedNetworkFunction(entry.first);++count;}
  }
  if(count<40)throw std::runtime_error("Incomplete SDK dynamic networking fence");
  for(const auto& expected:known_network){bool found=false;for(const auto& entry:*registry)if(entry.first&&std::strcmp(entry.first,expected.name)==0&&entry.second==expected.function)found=true;if(!found)throw std::runtime_error("Known SDK network export missing");}
  registry_entries.store(count);return count;
}
uint64_t NetworkRegistryEntries(){return registry_entries.load();}
}

extern "C" void __imp__XamInputGetCapabilities(PPCContext& __restrict ctx,uint8_t* base) {
  uint32_t result = 0;
  if (forza2::qualification::Capabilities(ctx.r3.u32,ctx.r5.u32,base,result)) ctx.r3.u64=result;
  else Forward("__imp__XamInputGetCapabilities",ctx,base);
}
extern "C" void __imp__XamInputSetState(PPCContext& __restrict ctx,uint8_t* base) {
  if (!forza2::qualification::Enabled()) {Forward("__imp__XamInputSetState",ctx,base);return;}
  forza2::qualification::ForceCall();ctx.r3.u64 = ctx.r3.u32 ? 1167 : 0;
}
extern "C" void __imp__XamInputGetKeystroke(PPCContext& __restrict ctx,uint8_t* base) {
  if (!forza2::qualification::Enabled()) {Forward("__imp__XamInputGetKeystroke",ctx,base);return;}
  ctx.r3.u64 = ctx.r3.u32 ? 1167 : 4306;
}
