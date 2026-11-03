#include "provider_free.h"
#include <cstring>
#include <windows.h>
#include <rex/ppc/context.h>

namespace {
using GuestFunction = void (*)(PPCContext&, uint8_t*);
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
