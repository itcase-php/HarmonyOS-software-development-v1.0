/* Compile/link prerequisite for the fontconfig C99 cross-configure cache.
 * Must also execute on the device before accepting the fontconfig runtime. */
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static int check_copy(const char* format, ...)
{
    char short_buffer[2];
    char full_buffer[8];
    va_list original, copy;
    va_start(original, format);
    va_copy(copy, original);
    int length = vsnprintf(short_buffer, sizeof(short_buffer), format, original);
    int copied_length = vsnprintf(full_buffer, sizeof(full_buffer), format, copy);
    va_end(copy);
    va_end(original);
    return length == 3 && copied_length == 3 &&
        strcmp(short_buffer, "1") == 0 && strcmp(full_buffer, "111") == 0;
}

int main(void)
{
    char buffer[2];
    if (snprintf(buffer, sizeof(buffer), "%s", "111") != 3 ||
        strcmp(buffer, "1") != 0 || !check_copy("%d", 111) || !check_copy("%s", "111"))
    {
        fputs("C99 formatting/va_copy check failed\n", stderr);
        return 1;
    }
    puts("PASS: C99 formatting and va_copy");
    return 0;
}
