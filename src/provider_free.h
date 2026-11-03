#pragma once
#include <cstdint>
#include <functional>
#include <filesystem>
#include <rex/runtime.h>
namespace rex {struct PathConfig;}

namespace forza2::qualification {
// Off by default. Selected before any input backend is constructed.
bool Enabled();
void Configure(rex::RuntimeConfig& config);
uint64_t ArmNetworkRegistry();
uint64_t NetworkRegistryEntries();
void PrivatePaths(rex::PathConfig& paths,const std::filesystem::path& executable_folder);
void Start(std::function<void()> close);
void Stop();
void Frame();
void PresentReturned();
bool Input(uint32_t user, uint32_t pointer, uint8_t* base, uint32_t& result);
bool Capabilities(uint32_t user, uint32_t pointer, uint8_t* base, uint32_t& result);
void NetworkCall();
void ForceCall();
}
