#pragma once
#include <stddef.h>
#include <stdint.h>
int fm2_pf_read(const char *path,char *text,size_t capacity,unsigned long *error);
int fm2_pf_value(const char *text,const char *key,char *value,size_t capacity);
int fm2_pf_decimal(const char *text,uint64_t *value);
int fm2_pf_publish(const char *path,const char *text,unsigned long *error);
