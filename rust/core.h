#pragma once
#include <stdint.h>

// Keep in sync with rust/src/lib.rs
char *core_version(void);
void core_free_string(char *p);
int64_t core_add(int64_t a, int64_t b);
