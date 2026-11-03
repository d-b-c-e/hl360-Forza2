// Reproduce the generated vrfin consumer that failed the complete link without
// the project's existing SSE4.1 baseline. No runtime, game or host subsystem.
#include <rex/ppc/context.h>
#include <cstdio>
int main(){
  alignas(16) float input[8]={0.5f,1.5f,2.5f,-0.5f,-1.5f,-2.5f,3.5f,-3.5f};
  const float expected[8]={0,2,2,0,-2,-2,4,-4};
  alignas(16) float output[8];
  for(int offset=0;offset<8;offset+=4)
    simde_mm_store_ps(output+offset,simde_mm_round_ps(simde_mm_load_ps(input+offset),SIMDE_MM_FROUND_TO_NEAREST_INT|SIMDE_MM_FROUND_NO_EXC));
  for(int i=0;i<8;++i)if(output[i]!=expected[i])return 1;
  std::puts("{\"pass\":true,\"roundToEvenCases\":8}");return 0;
}
