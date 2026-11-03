/* Real Win32 reader/publisher regression. No SDL, renderer, input or game. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include "provider_free_io.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned checks;static char path[1000];static volatile LONG done;
#define CHECK(x) do{++checks;if(!(x)){fprintf(stderr,"line %d: %s winerr=%lu\n",__LINE__,#x,GetLastError());exit(1);}}while(0)
static DWORD WINAPI writer(void *p){
 unsigned id=(unsigned)(uintptr_t)p;char text[256];unsigned long error;
 for(unsigned n=0;n<250;n++){snprintf(text,sizeof text,"nonce=0123456789abcdef0123456789abcdef\nwriter=%u\nvalue=%u\n",id,n);if(!fm2_pf_publish(path,text,&error))return error?error:1;Sleep(1);}
 InterlockedIncrement(&done);return 0;
}
int main(int argc,char **argv){
 CHECK(argc==2);CHECK(strlen(argv[1])<900);snprintf(path,sizeof path,"%s\\active.txt",argv[1]);
 CHECK(CreateDirectoryA(argv[1],NULL));char text[4096],value[64];unsigned long error;uint64_t n;
 CHECK(!fm2_pf_read(path,text,sizeof text,&error));
 CHECK(fm2_pf_publish(path,"nonce=first\n",&error));
 HANDLE held=CreateFileA(path,GENERIC_READ,7,NULL,OPEN_EXISTING,0,NULL);CHECK(held!=INVALID_HANDLE_VALUE);
 CHECK(fm2_pf_publish(path,"nonce=second\n",&error));
 CHECK(fm2_pf_read(path,text,sizeof text,&error)&&!strcmp(text,"nonce=second\n"));
 DWORD z;CHECK(ReadFile(held,text,sizeof text-1,&z,NULL));text[z]=0;CHECK(!strcmp(text,"nonce=first\n"));CloseHandle(held);
 CHECK(fm2_pf_publish(path,"partial",&error));CHECK(!fm2_pf_read(path,text,sizeof text,&error));
 CHECK(!fm2_pf_value("nonce=a\nnonce=b\n","nonce",value,sizeof value));
 CHECK(fm2_pf_value("other=1\r\nnonce=ok\r\n","nonce",value,sizeof value)&&!strcmp(value,"ok"));
 CHECK(!fm2_pf_value("nonce=overlong\n","nonce",value,3));
 CHECK(fm2_pf_decimal("134077596050000000",&n)&&n==134077596050000000ULL);
 CHECK(!fm2_pf_decimal("+1",&n));CHECK(!fm2_pf_decimal("1z",&n));CHECK(!fm2_pf_decimal("",&n));CHECK(!fm2_pf_decimal("99999999999999999999",&n));
 CHECK(fm2_pf_publish(path,"nonce=0123456789abcdef0123456789abcdef\nwriter=0\nvalue=0\n",&error));
 HANDLE a=CreateThread(NULL,0,writer,(void*)1,0,NULL),b=CreateThread(NULL,0,writer,(void*)2,0,NULL);CHECK(a&&b);
 unsigned reads=0;ULONGLONG deadline=GetTickCount64()+10000;while(InterlockedCompareExchange(&done,0,0)<2){
  CHECK(GetTickCount64()<deadline);
  if(fm2_pf_read(path,text,sizeof text,&error)){
   CHECK(fm2_pf_value(text,"nonce",value,sizeof value)&&!strcmp(value,"0123456789abcdef0123456789abcdef"));
   CHECK(fm2_pf_value(text,"writer",value,sizeof value)&&fm2_pf_decimal(value,&n)&&n<=2);
   CHECK(fm2_pf_value(text,"value",value,sizeof value)&&fm2_pf_decimal(value,&n)&&n<250);++reads;
  }Sleep(1);
 }
 CHECK(WaitForSingleObject(a,5000)==WAIT_OBJECT_0&&WaitForSingleObject(b,5000)==WAIT_OBJECT_0);
 DWORD ac,bc;CHECK(GetExitCodeThread(a,&ac)&&GetExitCodeThread(b,&bc)&&!ac&&!bc);CloseHandle(a);CloseHandle(b);CHECK(reads>10);
 CHECK(GetFileAttributesA(path)!=INVALID_FILE_ATTRIBUTES);
 printf("PASS provider-free production IO: %u checks, %u complete concurrent reads, held delete-sharing reader, partial/missing/duplicate/decimal rejection\n",checks,reads);return 0;
}
