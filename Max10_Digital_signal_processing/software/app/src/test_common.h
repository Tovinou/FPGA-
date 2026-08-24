#ifndef TEST_COMMON_H
#define TEST_COMMON_H

#include <stdint.h>

void test_wait_cycles(unsigned int count, uint32_t (*read_status)(void));
int test_check(const char *name, int condition);

#endif