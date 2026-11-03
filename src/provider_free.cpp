// Opt-in native qualification. No global input, host pad, haptics or sockets.
#include "provider_free.h"
#include <algorithm>
#include <atomic>
#include <charconv>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <stdexcept>
#include <string>
#include <windows.h>
#include <rex/cvar.h>
#include <rex/input/input_system.h>
#include <rex/audio/audio_system.h>
#include <rex/audio/audio_driver.h>
extern "C" {
#include "provider_free_io.h"
}

REXCVAR_DEFINE_BOOL(provider_free, false, "Qualification", "Isolated native qualification; no host input or network")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);
REXCVAR_DEFINE_STRING(provider_free_root, "", "Qualification", "Private command/status directory")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);
REXCVAR_DEFINE_STRING(provider_free_nonce, "", "Qualification", "32 lowercase hex digits")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);

namespace forza2::qualification {
using rex::X_STATUS;
namespace {
struct Command {
  uint64_t seq = 0;
  int buttons = 0, lt = 0, rt = 0, lx = 0, ly = 0, rx = 0, ry = 0, quit = 0;
};
std::mutex mutex;
Command command;
std::string root, nonce, reason;
std::function<void()> close_callback;
uint64_t started = 0, accepted = 0, published = 0, reads = 0, frames = 0;
uint64_t consumed_seq = 0, consumed = 0, packet = 0, birth = 0;
std::atomic<uint64_t> network_calls{0}, force_calls{0};
std::atomic<uint64_t> audio_systems{0}, audio_drivers{0}, audio_frames{0}, audio_failures{0};
bool configured = false, running = false, close_sent = false;

// Silent guest-audio acknowledgment at 256 samples/48kHz. No host audio
// backend or fallback is constructed. Uses the existing SDK worker thread.
class SilentAudioDriver final : public rex::audio::AudioDriver {
 public:
  SilentAudioDriver(rex::memory::Memory* memory,rex::thread::Semaphore* semaphore)
      : AudioDriver(memory),semaphore_(semaphore),timer_(CreateWaitableTimerExW(nullptr,nullptr,CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,TIMER_ALL_ACCESS)) {}
  ~SilentAudioDriver() override {if(timer_) CloseHandle(timer_);}
  bool valid() const {return timer_!=nullptr;}
  void SubmitFrame(uint32_t) override {
    LARGE_INTEGER due;due.QuadPart=-53333; // 256/48000 seconds, relative100ns units.
    if (!SetWaitableTimer(timer_,&due,0,nullptr,nullptr,FALSE)||WaitForSingleObject(timer_,50)!=WAIT_OBJECT_0) ++audio_failures;
    if (!semaphore_->Release(1,nullptr)) ++audio_failures;
    ++audio_frames;
  }
 private:
  rex::thread::Semaphore* semaphore_;
  HANDLE timer_;
};
class SilentAudioSystem final : public rex::audio::AudioSystem {
 public:
  explicit SilentAudioSystem(rex::runtime::FunctionDispatcher* dispatcher):AudioSystem(dispatcher) {++audio_systems;}
  X_STATUS CreateDriver(size_t,rex::thread::Semaphore* semaphore,rex::audio::AudioDriver** out) override {
    if (!semaphore||!out) return X_STATUS_INVALID_PARAMETER;
    *out=nullptr;auto* driver=new SilentAudioDriver(memory_,semaphore);
    if(!driver->valid()){delete driver;++audio_failures;return X_STATUS_UNSUCCESSFUL;}
    *out=driver;++audio_drivers;return X_STATUS_SUCCESS;
  }
  void DestroyDriver(rex::audio::AudioDriver* driver) override {delete driver;}
};

void Fail(const char* why) {
  if (reason.empty()) reason = why;
}
bool Number(const char* text, const char* key, int lo, int hi, int& out) {
  char value[64];
  if (!fm2_pf_value(text, key, value, sizeof value)) return false;
  auto [end, error] = std::from_chars(value, value + std::strlen(value), out);
  return error == std::errc{} && end == value + std::strlen(value) && out >= lo && out <= hi;
}
bool ReadCommand(const char* text, Command& out) {
  char value[64]; int version = 0;
  if (std::count(text, text + std::strlen(text), '\n') != 11 ||
      !fm2_pf_value(text, "nonce", value, sizeof value) || nonce != value ||
      !fm2_pf_value(text, "seq", value, sizeof value) || !fm2_pf_decimal(value, &out.seq) || !out.seq)
    return false;
  return Number(text,"buttons",0,65535,out.buttons) && Number(text,"lt",0,255,out.lt) &&
    Number(text,"rt",0,255,out.rt) && Number(text,"lx",-32768,32767,out.lx) &&
    Number(text,"ly",-32768,32767,out.ly) && Number(text,"rx",-32768,32767,out.rx) &&
    Number(text,"ry",-32768,32767,out.ry) && Number(text,"quit",0,1,out.quit) &&
    Number(text,"version",1,1,version);
}
bool Parse(const char* text, Command& out) {
  return ReadCommand(text,out);
}
void Poll() {
  const auto now = GetTickCount64();
  if (now - reads < 8) return;
  reads = now;
  char text[2048]; unsigned long error = 0;
  if (fm2_pf_read((root + "/command.txt").c_str(), text, sizeof text, &error)) {
    Command next;
    if (!Parse(text,next) || next.seq < command.seq) {command = {}; Fail("command-invalid");}
    else if (next.seq > command.seq) {command = next; accepted = now;}
  }
  if (now - accepted > 1500) {command = {}; Fail("command-stale");}
  if (now - started > 540000) Fail("native-deadline");
  if (audio_failures.load()) Fail("silent-audio-ack");
}
void Publish(bool final = false) {
  auto now = GetTickCount64();
  if (!final && now - published < 80) return;
  published = now;
  char text[2048];
  std::snprintf(text, sizeof text,
    "{\"schema\":\"fm2.provider-free@1\",\"nonce\":\"%s\",\"pid\":%lu,\"birthFileTime\":%llu,"
    "\"noHost\":true,\"controllers\":0,\"networkBlocked\":true,\"audio\":\"silent-ack\","
    "\"seq\":%llu,\"consumedSeq\":%llu,\"consumed\":%llu,\"frames\":%llu,\"networkCalls\":%llu,"
    "\"forceCalls\":%llu,\"audioSystems\":%llu,\"audioDrivers\":%llu,\"audioFrames\":%llu,\"audioFailures\":%llu,\"buttons\":%d,\"lt\":%d,\"rt\":%d,\"lx\":%d,"
    "\"elapsedMs\":%llu,\"closing\":%s,\"final\":%s,\"reason\":\"%s\"}\n",
    nonce.c_str(),GetCurrentProcessId(),birth,command.seq,consumed_seq,consumed,frames,
    network_calls.load(),force_calls.load(),audio_systems.load(),audio_drivers.load(),audio_frames.load(),audio_failures.load(),command.buttons,command.lt,command.rt,command.lx,
    now-started,close_sent?"true":"false",final?"true":"false",reason.c_str());
  unsigned long error = 0;
  if (!fm2_pf_publish((root+"/status.json").c_str(),text,&error)) Fail("status-write");
}
void Trace() {
  char text[512];
  std::snprintf(text,sizeof text,
    "{\"nonce\":\"%s\",\"seq\":%llu,\"frame\":%llu,\"packet\":%llu,\"buttons\":%d,\"lt\":%d,\"rt\":%d,\"lx\":%d,\"ly\":%d,\"rx\":%d,\"ry\":%d}\n",
    nonce.c_str(),command.seq,frames,packet,command.buttons,command.lt,command.rt,command.lx,command.ly,command.rx,command.ry);
  HANDLE file = CreateFileA((root+"/consumed.jsonl").c_str(),FILE_APPEND_DATA,7,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
  DWORD written = 0, bytes = DWORD(std::strlen(text));
  if (file == INVALID_HANDLE_VALUE) {Fail("trace-open"); return;}
  if (!WriteFile(file,text,bytes,&written,nullptr) || written != bytes) Fail("trace-write");
  CloseHandle(file);
}
bool Pointer(uint32_t pointer, unsigned size) {
  return pointer >= 0x1000 && uint64_t(pointer) + size <= 0x100000000ull;
}
}
bool Enabled() {
  static std::atomic<bool> latched{false};
  if (REXCVAR_GET(provider_free)) latched.store(true);
  return latched.load();
}
void Configure(rex::RuntimeConfig& config) {
  if (!Enabled()) return;
  // Real SDK type, with ZERO drivers; ReXApp's AttachWindow/static_cast remains valid.
  config.input_factory = [](bool) -> std::unique_ptr<rex::system::IInputSystem> {
    return std::make_unique<rex::input::InputSystem>(nullptr);
  };
  config.audio_factory = [](rex::runtime::FunctionDispatcher* dispatcher) -> std::unique_ptr<rex::system::IAudioSystem> {
    return std::make_unique<SilentAudioSystem>(dispatcher);
  };
  configured = true;
}
void Start(std::function<void()> close) {
  if (!Enabled()) return;
  std::lock_guard lock(mutex);
  root = REXCVAR_GET(provider_free_root); nonce = REXCVAR_GET(provider_free_nonce);
  if (!configured || root.empty() || root.size()>220 || nonce.size()!=32 ||
      nonce.find_first_not_of("0123456789abcdef")!=std::string::npos)
    throw std::runtime_error("Invalid isolated qualification configuration");
  FILETIME creation,exit,kernel,user;
  if (!GetProcessTimes(GetCurrentProcess(),&creation,&exit,&kernel,&user))
    throw std::runtime_error("Qualification process identity unavailable");
  birth = (uint64_t(creation.dwHighDateTime)<<32)|creation.dwLowDateTime;
  started = accepted = GetTickCount64(); close_callback = std::move(close); running = true;
  Poll(); Publish();
}
void Stop() {
  if (!Enabled()) return;
  std::lock_guard lock(mutex);
  if (running) Publish(true);
  running = false; close_callback = {};
}
void Frame() {
  if (!Enabled()) return;
  std::function<void()> close;
  {
    std::lock_guard lock(mutex);
    if (!running) return;
    ++frames; Poll();
    if ((!reason.empty() || command.quit) && !close_sent) {close_sent = true; close = close_callback;}
    Publish();
  }
  if (close) close();
}
bool Input(uint32_t user, uint32_t pointer, uint8_t* base, uint32_t& result) {
  if (!Enabled()) return false;
  std::lock_guard lock(mutex);
  result = 1167;
  if (!running || user || !Pointer(pointer,16)) return true;
  Poll();
  auto* state = reinterpret_cast<rex::input::X_INPUT_STATE*>(base+pointer);
  std::memset(state,0,sizeof *state);
  state->packet_number = uint32_t(++packet);
  if (reason.empty()) {
    state->gamepad.buttons = uint16_t(command.buttons);
    state->gamepad.left_trigger = uint8_t(command.lt); state->gamepad.right_trigger = uint8_t(command.rt);
    state->gamepad.thumb_lx = int16_t(command.lx); state->gamepad.thumb_ly = int16_t(command.ly);
    state->gamepad.thumb_rx = int16_t(command.rx); state->gamepad.thumb_ry = int16_t(command.ry);
  }
  ++consumed;
  if (command.seq != consumed_seq) {consumed_seq = command.seq; Trace();}
  result = 0;
  return true;
}
bool Capabilities(uint32_t user,uint32_t pointer,uint8_t* base,uint32_t& result) {
  if (!Enabled()) return false;
  result = 1167;
  if (user || !Pointer(pointer,sizeof(rex::input::X_INPUT_CAPABILITIES))) return true;
  auto* caps = reinterpret_cast<rex::input::X_INPUT_CAPABILITIES*>(base+pointer);
  std::memset(caps,0,sizeof *caps); caps->type = 1; caps->sub_type = 1;
  result = 0; return true;
}
void NetworkCall() {++network_calls;}
void ForceCall() {++force_calls;}
}
