#include <stdio.h>

#include "test_common.h"

void test_wait_cycles(unsigned int count, uint32_t (*read_status)(void))
{
    volatile unsigned int i;

    for (i = 0; i < count; ++i)
    {
        (void)read_status();
    }
}

int test_check(const char *name, int condition)
{
    printf("[%s] %s\n", condition ? "PASS" : "FAIL", name);
    return condition ? 0 : 1;
}