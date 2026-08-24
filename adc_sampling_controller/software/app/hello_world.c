/*
 * Copyright (C) 2021 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <stdio.h>

int main() {
    for (int i = 0; i < 1000; ++i) {
        printf("Hello world, this is the Nios V/m cpu checking in %d...\n", i);
    }
    printf("Bye world!\n");
    return 0;
}
