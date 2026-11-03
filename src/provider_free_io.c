/* Bounded snapshots; same whole-object FILE_RENAME_INFO_EX contract as the
 * qualified OutRun publisher. No delete-then-move or partial status publication. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include "provider_free_io.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int fm2_pf_read(const char *path,char *text,size_t capacity,unsigned long *error){
 if(error)*error=0;if(!path||!text||capacity<2||capacity>65536)return 0;
 HANDLE h=CreateFileA(path,GENERIC_READ,7,NULL,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,NULL);
 if(h==INVALID_HANDLE_VALUE){if(error)*error=GetLastError();return 0;}
 BY_HANDLE_FILE_INFORMATION info;LARGE_INTEGER size;DWORD read;int ok=0;
 if(!GetFileInformationByHandle(h,&info)||!GetFileSizeEx(h,&size))goto done;
 if((info.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT))||size.QuadPart<1||size.QuadPart>=(LONGLONG)capacity){SetLastError(ERROR_INVALID_DATA);goto done;}
 if(!ReadFile(h,text,(DWORD)size.QuadPart,&read,NULL))goto done;
 if(read!=(DWORD)size.QuadPart||memchr(text,0,read)){SetLastError(ERROR_INVALID_DATA);goto done;}
 if(text[read-1]!='\n'){SetLastError(ERROR_MORE_DATA);goto done;}
 text[read]=0;ok=1;
done: if(!ok&&error)*error=GetLastError();CloseHandle(h);return ok;
}
int fm2_pf_value(const char *text,const char *key,char *value,size_t capacity){
 if(!text||!key||!value||!capacity)return 0;size_t key_len=strlen(key);int found=0;
 for(const char *line=text;*line;){size_t n=strcspn(line,"\r\n");
  if(n>key_len&&!strncmp(line,key,key_len)&&line[key_len]=='='){
   size_t z=n-key_len-1;if(found++||z>=capacity)return 0;memcpy(value,line+key_len+1,z);value[z]=0;
  }
  line+=n;while(*line=='\r'||*line=='\n')++line;
 }
 return found==1;
}
int fm2_pf_decimal(const char *text,uint64_t *value){
 if(!text||!*text||!value||strlen(text)>19||strspn(text,"0123456789")!=strlen(text))return 0;
 *value=strtoull(text,NULL,10);return 1;
}
typedef struct Rename {DWORD flags;HANDLE root;DWORD length;WCHAR name[1];} Rename;
int fm2_pf_publish(const char *path,const char *text,unsigned long *error){
 static LONG sequence;char temporary[1200];WCHAR full[1200],name[1200];DWORD written=0;int ok=0;
 if(error)*error=0;if(!path||!text||strlen(path)>1000||strlen(text)>16384)return 0;
 if(!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,path,-1,name,1200))return 0;
 DWORD full_length=GetFullPathNameW(name,1200,full,NULL);if(!full_length||full_length>=1200)return 0;
 snprintf(temporary,sizeof temporary,"%s.%lu.%ld.tmp",path,GetCurrentProcessId(),InterlockedIncrement(&sequence));
 HANDLE h=CreateFileA(temporary,GENERIC_WRITE|DELETE|SYNCHRONIZE,7,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);
 if(h==INVALID_HANDLE_VALUE){if(error)*error=GetLastError();return 0;}
 size_t size=strlen(text);Rename *rename=NULL;
 if(!WriteFile(h,text,(DWORD)size,&written,NULL)||written!=(DWORD)size)goto done;
 size_t bytes=wcslen(full)*sizeof(WCHAR),total=sizeof(Rename)+bytes;
 rename=(Rename*)calloc(1,total);if(!rename){SetLastError(ERROR_OUTOFMEMORY);goto done;}
 rename->flags=3; /* REPLACE_IF_EXISTS | POSIX_SEMANTICS; existing held readers stay valid */
 rename->length=(DWORD)bytes;memcpy(rename->name,full,bytes);
 ok=SetFileInformationByHandle(h,(FILE_INFO_BY_HANDLE_CLASS)22,rename,(DWORD)total)!=0;
done:
 if(!ok&&error)*error=GetLastError();free(rename);CloseHandle(h);
 if(!ok)DeleteFileA(temporary);return ok;
}
