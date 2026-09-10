/* Smoke for libcirc.a: print the version JSON, then the analysis JSON for
 * an inverter held entirely in memory. Exits non-zero on any status but 0.
 * Built and run by `zig build libcirc-smoke`. */
#include <stdio.h>
#include <string.h>

#include "libcirc.h"

static const char request[] =
    "{\"root\": \"/playground/main.circ\","
    " \"files\": {\"/playground/main.circ\": \"input a\\nnot n(in=a)\\noutput o(in=n.out)\\n\"},"
    " \"options\": {\"color\": \"never\"}}";

static int print_result(const char *label, uint32_t status) {
    printf("%s status=%u\n", label, (unsigned)status);
    fwrite(circ_result_ptr(), 1, circ_result_len(), stdout);
    printf("\n");
    return status == CIRC_STATUS_OK ? 0 : 1;
}

int main(void) {
    int failed = 0;
    failed |= print_result("version", circ_version());

    size_t len = strlen(request);
    uint8_t *buf = circ_alloc(len);
    if (!buf) return 2;
    memcpy(buf, request, len);
    failed |= print_result("analyze", circ_analyze(buf, len));
    failed |= print_result("preview", circ_preview(buf, len));
    circ_free(buf, len);
    circ_reset();
    return failed;
}
