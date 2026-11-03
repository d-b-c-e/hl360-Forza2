#pragma once
#include <cstdint>
#include <functional>
#include <rex/runtime.h>

namespace forza2::qualification {
// Off by default. Selected before any input backend is constructed.
bool Enabled();
void Configure(rex::RuntimeConfig& config);
void Start(std::function<void()> close);
void Stop();
void Frame();
bool Input(uint32_t user, uint32_t pointer, uint8_t* base, uint32_t& result);
bool Capabilities(uint32_t user, uint32_t pointer, uint8_t* base, uint32_t& result);
void NetworkCall();
void ForceCall();
}
