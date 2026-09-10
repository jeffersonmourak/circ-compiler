/* libcirc — circ's compiler front end as a C library.
 *
 * Every call takes one JSON request (see DOCS/libcirc-api.md):
 *   {"root": "/p/main.circ",
 *    "files": {"/p/main.circ": "...", "/p/dep.circ": "..."},
 *    "options": {...}}
 * and leaves its result in a library-owned buffer read back through
 * circ_result_ptr()/circ_result_len(). The buffer is valid until the next
 * circ_* call. Not thread-safe: all state is process-global.
 */
#ifndef LIBCIRC_H
#define LIBCIRC_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CIRC_STATUS_OK 0            /* result = artifact bytes / text / JSON        */
#define CIRC_STATUS_DIAGNOSTICS 1   /* result = {"files":[...],"diagnostics":[...],"symbols":[],"references":[]} */
#define CIRC_STATUS_BAD_REQUEST 2   /* result = {"error":"..."}                     */
#define CIRC_STATUS_REFUSED 3       /* result = {"error":"..."} (cap, layout)       */
#define CIRC_STATUS_OUT_OF_MEMORY 4 /* result empty                                 */
#define CIRC_STATUS_INTERNAL 5      /* result = {"error":"<stage>: <ErrName>"}      */

/* Request buffers: fill what circ_alloc returns, free it with circ_free
 * after the call. The library never keeps a pointer to a request. */
uint8_t *circ_alloc(size_t len);
void circ_free(uint8_t *ptr, size_t len);

/* Status 0; result = {"version":..,"revision":..,"topology_version":..,
 * "full_version":..,"parser":..,"parser_runtime_sha256":..,"grammar_sha256":..} */
uint32_t circ_version(void);

/* --analyze: status 0 with the analysis JSON; 2 on a bad request; 5 on an
 * internal failure. */
uint32_t circ_analyze(const uint8_t *req, size_t len);
/* circ-compile in.circ -o out.wasm: status 0 with the .wasm bytes. */
uint32_t circ_compile(const uint8_t *req, size_t len);
/* --preview: status 0 with the schematic text; 3 if the layout failed. */
uint32_t circ_preview(const uint8_t *req, size_t len);
/* --truth-table: status 0 with the table; 3 when the input cap is exceeded. */
uint32_t circ_truth_table(const uint8_t *req, size_t len);

/* Library-owned; valid until the next circ_* call. */
const uint8_t *circ_result_ptr(void);
size_t circ_result_len(void);

/* Drops the result buffer, the call arena and the engine arena. Returns 0. */
uint32_t circ_reset(void);

#ifdef __cplusplus
}
#endif

#endif /* LIBCIRC_H */
