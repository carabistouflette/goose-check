/* SPDX-License-Identifier: Apache-2.0 */
#include <stdio.h>
int main(void) {
    int byte;
    while ((byte = getchar()) != EOF)
        if (putchar(byte) == EOF) return 1;
    return ferror(stdin) ? 1 : 0;
}
