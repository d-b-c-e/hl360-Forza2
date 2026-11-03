// Actual production consumer/export/factory tests. No app, renderer, hook,
// host input backend, game, socket or owner files are opened.
#include "../../src/provider_free.cpp"
#include "../../src/provider_free_network.cpp"
#include <rex/ppc/context.h>
#include <vector>

// The real frame_stats wrapper calls this inert original, not a GPU/runtime.
unsigned original_present_calls=0;
std::function<void()> fixture_present_probe;
extern "C" void __imp__sub_8236CB28(PPCContext&,uint8_t*){++original_present_calls;if(fixture_present_probe)fixture_present_probe();}
extern "C" void sub_8236CB28(PPCContext&,uint8_t*);

extern "C" void __imp__XamInputGetState(PPCContext&,uint8_t*);
extern "C" void __imp__XamInputGetCapabilities(PPCContext&,uint8_t*);
extern "C" void __imp__XamInputSetState(PPCContext&,uint8_t*);
extern "C" void __imp__XamInputGetKeystroke(PPCContext&,uint8_t*);
#define FM2_NET(name,result) extern "C" void __imp__##name(PPCContext&,uint8_t*);
#include "../../src/provider_free_network.def"
#undef FM2_NET

unsigned checks;
#define CHECK(condition) do {++checks;if(!(condition)){std::fprintf(stderr,"line %d: %s\n",__LINE__,#condition);return 1;}}while(0)
int main(int argc,char** argv) {
  CHECK(argc==2);
  using namespace forza2::qualification;
  using rex::X_STATUS;
  const std::string fixture_root=argv[1];
  CHECK(CreateDirectoryA(fixture_root.c_str(),nullptr));
  std::vector<uint8_t> memory(0x3000,0xcc); uint32_t result=0;
  CHECK(!Input(0,0x1000,memory.data(),result));
  PPCContext ordinary_present{};sub_8236CB28(ordinary_present,memory.data());
  CHECK(original_present_calls==1&&frames==0&&present_returns==0);original_present_calls=0;
  rex::RuntimeConfig ordinary; Configure(ordinary); CHECK(!ordinary.input_factory);
  REXCVAR_SET(provider_free,true);
  REXCVAR_SET(provider_free_root,fixture_root);
  REXCVAR_SET(provider_free_nonce,"0123456789abcdef0123456789abcdef");
  const auto private_live=std::filesystem::path(fixture_root)/"live";
  REXCVAR_SET(provider_free_root,private_live.string());
  rex::PathConfig paths;paths.user_data_root="C:/owner-sentinel";paths.update_data_root="C:/owner-update";
  PrivatePaths(paths,private_live/"bin");
  CHECK(paths.user_data_root==std::filesystem::path(fixture_root)/"user"&&paths.cache_root==std::filesystem::path(fixture_root)/"cache");
  CHECK(paths.game_data_root==std::filesystem::path(fixture_root)/"data"&&paths.update_data_root.empty());
  bool refused=false;try{PrivatePaths(paths,std::filesystem::path(fixture_root)/"owner-bin");}catch(const std::runtime_error&){refused=true;}CHECK(refused);
  REXCVAR_SET(provider_free_root,fixture_root);
  rex::RuntimeConfig config; Configure(config); CHECK(config.input_factory&&config.audio_factory);
  REXCVAR_SET(provider_free,false);CHECK(Enabled()); // One-way latch survives a late flag edit.
  rex::runtime::FunctionDispatcher dispatcher(nullptr,nullptr);
  auto audio=config.audio_factory(&dispatcher);
  auto* silent=dynamic_cast<SilentAudioSystem*>(audio.get());CHECK(silent!=nullptr);
  auto semaphore=rex::thread::Semaphore::Create(0,4);CHECK(semaphore!=nullptr);
  rex::audio::AudioDriver* output=nullptr;
  CHECK(silent->CreateDriver(0,nullptr,&output)==X_STATUS_INVALID_PARAMETER);
  CHECK(silent->CreateDriver(0,semaphore.get(),&output)==X_STATUS_SUCCESS);
  CHECK(dynamic_cast<SilentAudioDriver*>(output)!=nullptr);
  output->SubmitFrame(0xdeadbeef); // Must never read samples or open a device.
  CHECK(audio_systems.load()==1&&audio_drivers.load()==1&&audio_frames.load()==1&&audio_failures.load()==0);
  silent->DestroyDriver(output);audio.reset();
  auto input=config.input_factory(false); CHECK(input_systems.load()==1&&input->Setup()==0);
  auto* actual=static_cast<rex::input::InputSystem*>(input.get());
  rex::input::X_INPUT_STATE host_state{};
  CHECK(actual->GetState(0,&host_state)==1167);
  rex::input::X_INPUT_VIBRATION force{};force.left_motor_speed=65535;force.right_motor_speed=65535;
  CHECK(actual->SetState(0,&force)==1167);
  actual->Shutdown(); input.reset();
  auto make=[](int seq,int buttons,int lt,int rt,int lx,int quit){
    char text[512];std::snprintf(text,sizeof text,
      "version=1\nnonce=0123456789abcdef0123456789abcdef\nseq=%d\nbuttons=%d\nlt=%d\nrt=%d\nlx=%d\nly=0\nrx=0\nry=0\nquit=%d\n",
      seq,buttons,lt,rt,lx,quit);return std::string(text);
  };
  // Parse the actual production parser with malformed/range/nonce/duplicate data.
  nonce=REXCVAR_GET(provider_free_nonce);
  Command parsed;
  CHECK(Parse(make(1,65535,255,255,-32768,0).c_str(),parsed));
  CHECK(parsed.quit==0&&parsed.lx==-32768);
  CHECK(Parse(make(1,0,0,0,32767,1).c_str(),parsed)&&parsed.quit==1);
  for (auto bad: {make(0,0,0,0,0,0),make(1,65536,0,0,0,0),make(1,-1,0,0,0,0),
       make(1,0,-1,0,0,0),make(1,0,0,256,0,0),make(1,0,0,0,-32769,0),
       make(1,0,0,0,32768,0),make(1,0,0,0,0,2),make(1,0,0,0,0,0)+"seq=2\n"})
    CHECK(!Parse(bad.c_str(),parsed));
  auto wrong=make(1,0,0,0,0,0);wrong.replace(wrong.find("012345"),6,"abcdef");CHECK(!Parse(wrong.c_str(),parsed));
  auto publish=[&](const std::string& text){unsigned long error=0;return fm2_pf_publish((fixture_root+"/command.txt").c_str(),text.c_str(),&error);};
  CHECK(publish(make(1,4096,127,255,-16000,0)));
  int closes=0;Start([&]{++closes;});
  PPCContext ctx{};ctx.r3.u32=0;ctx.r5.u32=0x1000;
  __imp__XamInputGetState(ctx,memory.data());CHECK(ctx.r3.u32==0);
  auto* pad=reinterpret_cast<rex::input::X_INPUT_STATE*>(memory.data()+0x1000);
  CHECK(uint16_t(pad->gamepad.buttons)==4096&&pad->gamepad.right_trigger==255&&
        pad->gamepad.left_trigger==127&&int16_t(pad->gamepad.thumb_lx)==-16000);
  CHECK(uint32_t(pad->packet_number)==1);
  bool observed_in_flight=false;
  unsigned long in_flight_read_error=0;std::string in_flight_status;
  // GetTickCount64 can advance in coarse ticks. Wait on that same clock;
  // a fixed90ms sleep is insufficient to guarantee an80ms publication age.
  auto publication_ready=[](){for(int retry=0;retry<100;++retry){if(GetTickCount64()-published>=100)return true;Sleep(5);}return false;};
  fixture_present_probe=[&]{
    if(!publication_ready())return;
    ctx.r3.u32=0;ctx.r5.u32=0x1000;__imp__XamInputGetState(ctx,memory.data());
    char status[2048]{};
    const bool read=fm2_pf_read((fixture_root+"/status.json").c_str(),status,sizeof status,&in_flight_read_error)==1;
    in_flight_status=status;
    observed_in_flight=read&&
      std::strstr(status,"\"frames\":1,")&&std::strstr(status,"\"presentReturns\":0,")&&
      std::strstr(status,"\"presentInFlight\":1,")&&std::strstr(status,"\"consumed\":2,");
  };
  sub_8236CB28(ctx,memory.data());fixture_present_probe={};
  if(!observed_in_flight)std::fprintf(stderr,"inflight original=%u frames=%llu returns=%llu consumed=%llu readError=%lu reason=%s status=%s\n",original_present_calls,frames,present_returns,consumed,in_flight_read_error,reason.c_str(),in_flight_status.c_str());
  CHECK(original_present_calls==1);CHECK(observed_in_flight);CHECK(present_returns==1);
  CHECK(publication_ready());ctx.r3.u32=0;ctx.r5.u32=0x1000;__imp__XamInputGetState(ctx,memory.data());
  char completed_status[2048];unsigned long completed_error=0;
  CHECK(fm2_pf_read((fixture_root+"/status.json").c_str(),completed_status,sizeof completed_status,&completed_error)==1);
  CHECK(std::strstr(completed_status,"\"presentReturns\":1,")&&std::strstr(completed_status,"\"presentInFlight\":0,")&&std::strstr(completed_status,"\"consumed\":3,"));
  const auto diagnostic_consumed=consumed;
  ctx.r3.u32=1;__imp__XamInputGetState(ctx,memory.data());CHECK(ctx.r3.u32==1167);
  ctx.r3.u32=0;ctx.r5.u32=0;__imp__XamInputGetState(ctx,memory.data());CHECK(ctx.r3.u32==1167);
  ctx.r3.u32=0;ctx.r5.u32=0x1100;__imp__XamInputGetCapabilities(ctx,memory.data());CHECK(ctx.r3.u32==0);
  auto* caps=reinterpret_cast<rex::input::X_INPUT_CAPABILITIES*>(memory.data()+0x1100);
  CHECK(caps->type==1&&caps->sub_type==1&&uint16_t(caps->flags)==0&&uint16_t(caps->vibration.left_motor_speed)==0);
  ctx.r3.u32=0;__imp__XamInputSetState(ctx,memory.data());CHECK(ctx.r3.u32==0);
  ctx.r3.u32=0;__imp__XamInputGetKeystroke(ctx,memory.data());CHECK(ctx.r3.u32==4306);
  unsigned net_count=0;
  #define FM2_NET(name,expected) ctx.r3.u32=0;ctx.r4.u32=0x1200;__imp__##name(ctx,memory.data());CHECK(ctx.r3.u32==uint32_t(expected));++net_count;
  #include "../../src/provider_free_network.def"
  #undef FM2_NET
  CHECK(network_calls.load()==net_count&&net_count==40&&force_calls.load()==1);
  unsigned dynamic_count=0;
  for(const auto& entry:*RuntimeRegistry())if(entry.first&&std::strncmp(entry.first,"__imp__NetDll_",14)==0){
    CHECK(entry.second==FencedNetworkFunction(entry.first));
    ctx.r3.u32=0;ctx.r4.u32=0x1200;entry.second(ctx,memory.data());++dynamic_count;
  }
  CHECK(dynamic_count==NetworkRegistryEntries()&&dynamic_count>=40);
  CHECK(network_calls.load()==net_count+dynamic_count);
  CHECK(std::count(memory.begin()+0x1200,memory.begin()+0x1224,uint8_t(0))==36);
  CHECK(publish(make(2,0,0,0,0,0)));Sleep(25);
  ctx.r3.u32=0;ctx.r5.u32=0x1000;__imp__XamInputGetState(ctx,memory.data());CHECK(ctx.r3.u32==0);
  CHECK(uint16_t(pad->gamepad.buttons)==0&&pad->gamepad.right_trigger==0&&int16_t(pad->gamepad.thumb_lx)==0);
  CHECK(consumed_seq==2&&consumed==diagnostic_consumed+1);
  // Stale active input is neutral and triggers the same native close callback.
  CHECK(publish(make(3,4096,0,255,16000,0)));Sleep(25);
  ctx.r3.u32=0;__imp__XamInputGetState(ctx,memory.data());CHECK(ctx.r3.u32==0);
  Sleep(1600);ctx.r3.u32=0;__imp__XamInputGetState(ctx,memory.data());CHECK(ctx.r3.u32==0);
  CHECK(uint16_t(pad->gamepad.buttons)==0&&pad->gamepad.right_trigger==0&&int16_t(pad->gamepad.thumb_lx)==0);
  Frame();CHECK(closes==1&&reason=="command-stale");Frame();CHECK(closes==1);Stop();
  std::printf("{\"pass\":true,\"checks\":%u,\"networkExports\":%u,\"networkRegistryEntries\":%u,\"game\":false,\"hooks\":false,\"hostDrivers\":0}\n",checks,net_count,dynamic_count);
}
