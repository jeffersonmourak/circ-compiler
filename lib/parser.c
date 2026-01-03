/*
 * Auto-generated C parser by langlang.
 *
 * This file embeds the runtime unless RemoveLib=true.
 */

#include "lib/parser.h"

/* This tells the embedded runtime sources (c/vm.c, c/tree.c) to not include headers. */
#define LANGLANG_EMBEDDED 1

/* ---- BEGIN embedded runtime: c/vm.c ---- */
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#ifndef LANGLANG_EMBEDDED
#include "tree.h"
#include "vm.h"
#endif

void *ll_xrealloc(void *p, size_t n) {
  void *q = realloc(p, n);
  if (!q && n) {
    fprintf(stderr, "vm.c: out of memory\n");
    abort();
  }
  return q;
}

char *ll_xstrdup(const char *s) {
  if (!s) return NULL;
  size_t n = strlen(s);
  char *out = (char *)ll_xrealloc(NULL, n + 1);
  memcpy(out, s, n + 1);
  return out;
}

// Returns decoded codepoint in *r and bytes consumed (1..4).  On
// invalid input, returns U+FFFD and consumes 1 byte (Go-ish
// behavior).
static int ll_decode_rune(const uint8_t *data, int len, int offset, uint32_t *r) {
  if (offset >= len) {
    *r = 0;
    return 0;
  }
  uint8_t c0 = data[offset];
  if (c0 < 0x80) {
    *r = (uint32_t)c0;
    return 1;
  }
  // 2-byte
  if ((c0 & 0xE0) == 0xC0) {
    if (offset + 1 >= len) goto invalid;
    uint8_t c1 = data[offset + 1];
    if ((c1 & 0xC0) != 0x80) goto invalid;
    uint32_t cp = ((uint32_t)(c0 & 0x1F) << 6) | (uint32_t)(c1 & 0x3F);
    if (cp < 0x80) goto invalid; // overlong
    *r = cp;
    return 2;
  }
  // 3-byte
  if ((c0 & 0xF0) == 0xE0) {
    if (offset + 2 >= len) goto invalid;
    uint8_t c1 = data[offset + 1], c2 = data[offset + 2];
    if ((c1 & 0xC0) != 0x80 || (c2 & 0xC0) != 0x80) goto invalid;
    uint32_t cp = ((uint32_t)(c0 & 0x0F) << 12) |
      ((uint32_t)(c1 & 0x3F) << 6) |
      (uint32_t)(c2 & 0x3F);
    if (cp < 0x800) goto invalid; // overlong
    if (cp >= 0xD800 && cp <= 0xDFFF) goto invalid; // surrogate
    *r = cp;
    return 3;
  }
  // 4-byte
  if ((c0 & 0xF8) == 0xF0) {
    if (offset + 3 >= len) goto invalid;
    uint8_t c1 = data[offset + 1], c2 = data[offset + 2], c3 = data[offset + 3];
    if ((c1 & 0xC0) != 0x80 || (c2 & 0xC0) != 0x80 || (c3 & 0xC0) != 0x80)
      goto invalid;
    uint32_t cp = ((uint32_t)(c0 & 0x07) << 18) |
      ((uint32_t)(c1 & 0x3F) << 12) |
      ((uint32_t)(c2 & 0x3F) << 6) |
      (uint32_t)(c3 & 0x3F);
    if (cp < 0x10000 || cp > 0x10FFFF) goto invalid; // overlong/out of range
    *r = cp;
    return 4;
  }

 invalid:
  *r = 0xFFFD;
  return 1;
}

static inline uint16_t ll_decode_u16(const uint8_t *code, int offset) {
  return (uint16_t)code[offset] | ((uint16_t)code[offset + 1] << 8);
}

typedef struct {
  uint64_t w[8];
} ll_bitset512;

void ll_bitset512_set(ll_bitset512 *b, int id) {
  b->w[id >> 6] |= (uint64_t)1u << (id & 63);
}

bool ll_bitset512_has(const ll_bitset512 *b, int id) {
  return (b->w[id >> 6] & ((uint64_t)1u << (id & 63))) != 0;
}

typedef struct {
  uint8_t bits[32]; // 256 bits
} ll_charset;

bool ll_charset_has_byte(const ll_charset *cs, uint8_t b) {
  return (cs->bits[b >> 3] & (uint8_t)(1u << (b & 7))) != 0;
}

void ll_parsing_error_free(ll_parsing_error *e) {
  if (!e) return;
  free(e->message);
  free(e->label);
  memset(e, 0, sizeof(*e));
}

enum { LL_EXPECTED_LIMIT = 20 };

typedef struct {
  uint32_t a, b;
} ll_expected;

typedef struct {
  int cur;
  ll_expected arr[LL_EXPECTED_LIMIT];
} ll_expected_info;

static void ll_expected_info_clear(ll_expected_info *e) {
  e->cur = 0;
}

static void ll_expected_info_add(ll_expected_info *e, ll_expected s) {
  if (e->cur == LL_EXPECTED_LIMIT) return;
  if (s.b == 0) {
    if (s.a == 0 || s.a == ' ' || s.a == '\n' || s.a == '\r' || s.a == '\t') return;
  }
  for (int i = 0; i < e->cur; i++) {
    if (e->arr[i].a == s.a && e->arr[i].b == s.b) return;
  }
  e->arr[e->cur++] = s;
}

typedef struct { int key, val; } ll_i2i;
typedef struct { ll_i2i *items; int len, cap; } ll_i2i_map;

static void ll_i2i_map_init(ll_i2i_map *m) { memset(m, 0, sizeof(*m)); }
static void ll_i2i_map_free(ll_i2i_map *m) { free(m->items); memset(m, 0, sizeof(*m)); }

static void ll_i2i_map_put(ll_i2i_map *m, int key, int val) {
  for (int i = 0; i < m->len; i++) {
    if (m->items[i].key == key) { m->items[i].val = val; return; }
  }
  if (m->len + 1 > m->cap) {
    int cap = m->cap ? m->cap * 2 : 16;
    m->items = (ll_i2i *)ll_xrealloc(m->items, (size_t)cap * sizeof(ll_i2i));
    m->cap = cap;
  }
  m->items[m->len++] = (ll_i2i){.key = key, .val = val};
}

static bool ll_i2i_map_get(const ll_i2i_map *m, int key, int *out_val) {
  for (int i = 0; i < m->len; i++) {
    if (m->items[i].key == key) { *out_val = m->items[i].val; return true; }
  }
  return false;
}

typedef struct { char *key; int val; } ll_s2i;
typedef struct { ll_s2i *items; int len, cap; } ll_s2i_map;

static void ll_s2i_map_init(ll_s2i_map *m) { memset(m, 0, sizeof(*m)); }
static void ll_s2i_map_free(ll_s2i_map *m) {
  for (int i = 0; i < m->len; i++) free(m->items[i].key);
  free(m->items);
  memset(m, 0, sizeof(*m));
}

static bool ll_s2i_map_get(const ll_s2i_map *m, const char *key, int *out_val) {
  for (int i = 0; i < m->len; i++) {
    if (strcmp(m->items[i].key, key) == 0) { *out_val = m->items[i].val; return true; }
  }
  return false;
}

static void ll_s2i_map_put(ll_s2i_map *m, const char *key, int val) {
  for (int i = 0; i < m->len; i++) {
    if (strcmp(m->items[i].key, key) == 0) { m->items[i].val = val; return; }
  }
  if (m->len + 1 > m->cap) {
    int cap = m->cap ? m->cap * 2 : 16;
    m->items = (ll_s2i *)ll_xrealloc(m->items, (size_t)cap * sizeof(ll_s2i));
    m->cap = cap;
  }
  m->items[m->len++] = (ll_s2i){.key = ll_xstrdup(key), .val = val};
}

typedef struct {
  uint8_t *code;
  int code_len;

  const char **strs;
  int strs_len;

  ll_charset *sets;
  int sets_len;

  ll_expected **sexp;
  int *sexp_len;
  int sexp_cap;

  ll_s2i_map smap;
  ll_i2i_map rxps;
  ll_bitset512 rxbs;
} ll_bytecode;

void ll_bytecode_init(ll_bytecode *b) {
  memset(b, 0, sizeof(*b));
  ll_s2i_map_init(&b->smap);
  ll_i2i_map_init(&b->rxps);
}

void ll_bytecode_free(ll_bytecode *b) {
  free(b->code);
  free((void *)b->strs);
  free(b->sets);
  if (b->sexp) {
    for (int i = 0; i < b->sexp_cap; i++) {
      free(b->sexp[i]);
    }
  }
  free(b->sexp);
  free(b->sexp_len);
  ll_s2i_map_free(&b->smap);
  ll_i2i_map_free(&b->rxps);
  memset(b, 0, sizeof(*b));
}

ll_i2i_map ll_bytecode_compile_error_labels(ll_bytecode *b, const char **labels, const char **messages, int count) {
  ll_i2i_map out;
  ll_i2i_map_init(&out);
  if (count <= 0) return out;
  for (int i = 0; i < count; i++) {
    int label_id = 0, msg_id = 0;
    if (!ll_s2i_map_get(&b->smap, labels[i], &label_id)) continue;
    if (!ll_s2i_map_get(&b->smap, messages[i], &msg_id)) {
      // append new message to strs (growable copy)
      const char **new_strs = (const char **)ll_xrealloc((void *)b->strs, (size_t)(b->strs_len + 1) * sizeof(char *));
      b->strs = new_strs;
      b->strs[b->strs_len] = ll_xstrdup(messages[i]);
      msg_id = b->strs_len;
      b->strs_len++;
      ll_s2i_map_put(&b->smap, messages[i], msg_id);
    }
    ll_i2i_map_put(&out, label_id, msg_id);
  }
  return out;
}

// Virtual machine

typedef enum {
  LL_FRAME_BACKTRACKING = 0,
  LL_FRAME_CALL = 1,
  LL_FRAME_CAPTURE = 2,
} ll_frame_type;

typedef struct {
  int cursor;
  uint32_t pc;
  uint32_t cap_id;
  uint32_t nodes_start;
  uint32_t nodes_end;
  ll_frame_type t;
  bool predicate;
} ll_frame;

typedef struct {
  ll_frame *frames;
  int frames_len;
  int frames_cap;

  ll_node_id *node_arena;
  int node_arena_len;
  int node_arena_cap;

  ll_node_id *nodes;
  int nodes_len;
  int nodes_cap;

  ll_tree *tree;
} ll_stack;

static void ll_stack_init(ll_stack *s, ll_tree *t) {
  memset(s, 0, sizeof(*s));
  s->tree = t;
}

static void ll_stack_free(ll_stack *s) {
  free(s->frames);
  free(s->node_arena);
  free(s->nodes);
  memset(s, 0, sizeof(*s));
}

static void ll_stack_reset(ll_stack *s) {
  s->frames_len = 0;
  s->node_arena_len = 0;
  s->nodes_len = 0;
}

static void ll_stack_grow_frames(ll_stack *s, int need) {
  if (s->frames_len + need <= s->frames_cap) return;
  int cap = s->frames_cap ? s->frames_cap : 256;
  while (cap < s->frames_len + need) cap *= 2;
  s->frames = (ll_frame *)ll_xrealloc(s->frames, (size_t)cap * sizeof(ll_frame));
  s->frames_cap = cap;
}

static void ll_stack_grow_arena(ll_stack *s, int need) {
  if (s->node_arena_len + need <= s->node_arena_cap) return;
  int cap = s->node_arena_cap ? s->node_arena_cap : 256;
  while (cap < s->node_arena_len + need) cap *= 2;
  s->node_arena = (ll_node_id *)ll_xrealloc(s->node_arena, (size_t)cap * sizeof(ll_node_id));
  s->node_arena_cap = cap;
}

static void ll_stack_grow_nodes(ll_stack *s, int need) {
  if (s->nodes_len + need <= s->nodes_cap) return;
  int cap = s->nodes_cap ? s->nodes_cap : 256;
  while (cap < s->nodes_len + need) cap *= 2;
  s->nodes = (ll_node_id *)ll_xrealloc(s->nodes, (size_t)cap * sizeof(ll_node_id));
  s->nodes_cap = cap;
}

static void ll_stack_push(ll_stack *s, ll_frame f) {
  ll_stack_grow_frames(s, 1);
  f.nodes_start = (uint32_t)s->node_arena_len;
  f.nodes_end = f.nodes_start;
  s->frames[s->frames_len++] = f;
}

static ll_frame ll_stack_pop(ll_stack *s) {
  ll_frame f = s->frames[s->frames_len - 1];
  s->frames_len--;
  return f;
}

static ll_frame *ll_stack_top(ll_stack *s) {
  return &s->frames[s->frames_len - 1];
}

static int ll_stack_len(const ll_stack *s) {
  return s->frames_len;
}

static const ll_node_id *ll_stack_frame_nodes(const ll_stack *s, const ll_frame *f, int *out_len) {
  *out_len = (int)(f->nodes_end - f->nodes_start);
  if (*out_len <= 0) return NULL;
  return &s->node_arena[f->nodes_start];
}

static void ll_stack_capture(ll_stack *s, const ll_node_id *nodes, int nodes_len) {
  if (nodes_len <= 0) return;
  int n = s->frames_len;
  if (n > 0) {
    ll_stack_grow_arena(s, nodes_len);
    memcpy(&s->node_arena[s->node_arena_len], nodes, (size_t)nodes_len * sizeof(ll_node_id));
    s->node_arena_len += nodes_len;
    s->frames[n - 1].nodes_end = (uint32_t)s->node_arena_len;
    return;
  }
  ll_stack_grow_nodes(s, nodes_len);
  memcpy(&s->nodes[s->nodes_len], nodes, (size_t)nodes_len * sizeof(ll_node_id));
  s->nodes_len += nodes_len;
}

static void ll_stack_capture_one(ll_stack *s, ll_node_id id) {
  ll_stack_capture(s, &id, 1);
}

static void ll_stack_commit_captures_to_parent(ll_stack *s, uint32_t child_start, uint32_t child_end) {
  if (child_start == child_end) return;
  int n = s->frames_len;
  if (n == 0) {
    int len = (int)(child_end - child_start);
    ll_stack_grow_nodes(s, len);
    memcpy(&s->nodes[s->nodes_len], &s->node_arena[child_start], (size_t)len * sizeof(ll_node_id));
    s->nodes_len += len;
  } else {
    s->frames[n - 1].nodes_end = child_end;
  }
}

static void ll_stack_collect_captures(ll_stack *s) {
  int n = s->frames_len;
  if (n == 0) return;
  ll_frame *f = &s->frames[n - 1];
  if (f->nodes_end > f->nodes_start) {
    if (n == 1) {
      int len = (int)(f->nodes_end - f->nodes_start);
      ll_stack_grow_nodes(s, len);
      memcpy(&s->nodes[s->nodes_len], &s->node_arena[f->nodes_start], (size_t)len * sizeof(ll_node_id));
      s->nodes_len += len;
    } else {
      s->frames[n - 2].nodes_end = f->nodes_end;
    }
  }
}

static void ll_stack_truncate_arena(ll_stack *s, uint32_t pos) {
  if ((int)pos < 0) pos = 0;
  if ((int)pos > s->node_arena_len) pos = (uint32_t)s->node_arena_len;
  s->node_arena_len = (int)pos;
}

typedef struct {
  int ffp;
  ll_stack stack;
  ll_tree tree;
  ll_bytecode *bytecode;
  bool predicate;
  ll_expected_info expected;
  bool show_fails;
  ll_i2i_map err_labels;
  int cap_offset_id;
  int cap_offset_start;
} ll_vm;

typedef enum {
  LL_OP_HALT = 0,
  LL_OP_ANY,
  LL_OP_CHAR,
  LL_OP_RANGE,
  LL_OP_FAIL,
  LL_OP_FAIL_TWICE,
  LL_OP_CHOICE,
  LL_OP_CHOICE_PRED,
  LL_OP_CAP_COMMIT,
  LL_OP_CAP_PARTIAL_COMMIT,
  LL_OP_CAP_BACK_COMMIT,
  LL_OP_CALL,
  LL_OP_CAP_RETURN,
  LL_OP_JUMP,
  LL_OP_THROW,
  LL_OP_CAP_BEGIN,
  LL_OP_CAP_END,
  LL_OP_SET,
  LL_OP_SPAN,
  LL_OP_CAP_TERM,
  LL_OP_CAP_NON_TERM,
  LL_OP_COMMIT,
  LL_OP_BACK_COMMIT,
  LL_OP_PARTIAL_COMMIT,
  LL_OP_RETURN,
  LL_OP_CAP_TERM_BEGIN_OFFSET,
  LL_OP_CAP_NON_TERM_BEGIN_OFFSET,
  LL_OP_CAP_END_OFFSET,
} ll_opcode;

enum {
  LL_OP_ANY_SIZE = 1,
  LL_OP_CHAR_SIZE = 3,
  LL_OP_RANGE_SIZE = 5,
  LL_OP_SET_SIZE = 3,
  LL_OP_SPAN_SIZE = 3,
  LL_OP_CHOICE_SIZE = 3,
  LL_OP_COMMIT_SIZE = 3,
  LL_OP_FAIL_SIZE = 1,
  LL_OP_CALL_SIZE = 4,
  LL_OP_RETURN_SIZE = 1,
  LL_OP_JUMP_SIZE = 3,
  LL_OP_THROW_SIZE = 3,
  LL_OP_HALT_SIZE = 1,
  LL_OP_CAP_BEGIN_SIZE = 3,
  LL_OP_CAP_END_SIZE = 1,
  LL_OP_CAP_TERM_SIZE = 3,
  LL_OP_CAP_NON_TERM_SIZE = 5,
  LL_OP_CAP_TERM_BEGIN_OFFSET_SIZE = 1,
  LL_OP_CAP_NON_TERM_BEGIN_OFFSET_SIZE = 3,
  LL_OP_CAP_END_OFFSET_SIZE = 1,
};

static ll_frame ll_mk_backtrack_frame(int pc, int cursor) {
  return (ll_frame){
    .t = LL_FRAME_BACKTRACKING,
    .pc = (uint32_t)pc,
    .cursor = cursor,
    .cap_id = 0,
    .predicate = false,
  };
}

static ll_frame ll_mk_backtrack_pred_frame(int pc, int cursor) {
  ll_frame f = ll_mk_backtrack_frame(pc, cursor);
  f.predicate = true;
  return f;
}

static ll_frame ll_mk_capture_frame(int id, int cursor) {
  return (ll_frame){
    .t = LL_FRAME_CAPTURE,
    .cap_id = (uint32_t)id,
    .cursor = cursor,
    .pc = 0,
    .predicate = false,
  };
}

static ll_frame ll_mk_call_frame(int pc) {
  return (ll_frame){.t = LL_FRAME_CALL, .pc = (uint32_t)pc, .cursor = 0, .cap_id = 0, .predicate = false};
}

/* we don't want these in tree.h */
void ll_tree_bind_input(ll_tree *t, const uint8_t *input, int input_len);
void ll_tree_bind_strings(ll_tree *t, const char **strs, int strs_len);
void ll_tree_reset(ll_tree *t);
void ll_tree_set_root(ll_tree *t, ll_node_id id);
ll_node_id ll_tree_add_string(ll_tree *t, int start, int end);
ll_node_id ll_tree_add_sequence(ll_tree *t, const ll_node_id *children, int children_len, int start, int end);
ll_node_id ll_tree_add_node(ll_tree *t, int32_t name_id, ll_node_id child, int start, int end);
ll_node_id ll_tree_add_error(ll_tree *t, int32_t label_id, int32_t message_id, int start, int end);
ll_node_id ll_tree_add_error_with_child(ll_tree *t, int32_t label_id, int32_t message_id, ll_node_id child_id, int start, int end);

void ll_vm_init(ll_vm *vm, ll_bytecode *bc) {
  memset(vm, 0, sizeof(*vm));
  vm->bytecode = bc;
  vm->ffp = -1;
  ll_tree_init(&vm->tree);
  ll_stack_init(&vm->stack, &vm->tree);
  ll_i2i_map_init(&vm->err_labels);
  ll_tree_bind_strings(&vm->tree, bc->strs, bc->strs_len);
}

void ll_vm_free(ll_vm *vm) {
  ll_stack_free(&vm->stack);
  ll_tree_free(&vm->tree);
  ll_i2i_map_free(&vm->err_labels);
  memset(vm, 0, sizeof(*vm));
}

void ll_vm_set_show_fails(ll_vm *vm, bool show_fails) {
  vm->show_fails = show_fails;
  if (show_fails) {
    ll_expected_info_clear(&vm->expected);
  }
}

void ll_vm_set_label_messages(ll_vm *vm, const ll_i2i_map *labels) {
  ll_i2i_map_free(&vm->err_labels);
  ll_i2i_map_init(&vm->err_labels);
  if (!labels) return;
  for (int i = 0; i < labels->len; i++) {
    ll_i2i_map_put(&vm->err_labels, labels->items[i].key, labels->items[i].val);
  }
}

static void ll_vm_reset(ll_vm *vm) {
  ll_stack_reset(&vm->stack);
  ll_tree_reset(&vm->tree);
  vm->ffp = -1;
  if (vm->show_fails) {
    ll_expected_info_clear(&vm->expected);
  }
}

static void ll_vm_update_expected(ll_vm *vm, int cursor, ll_expected s) {
  bool should_clear = cursor > vm->ffp;
  bool should_add = cursor >= vm->ffp;
  if (should_clear) ll_expected_info_clear(&vm->expected);
  if (should_add) ll_expected_info_add(&vm->expected, s);
}

static void ll_vm_update_set_expected(ll_vm *vm, int cursor, uint16_t sid) {
  bool should_clear = cursor > vm->ffp;
  bool should_add = cursor >= vm->ffp;
  if (should_clear) ll_expected_info_clear(&vm->expected);
  if (!should_add) return;
  if (!vm->bytecode->sexp || sid >= (uint16_t)vm->bytecode->sexp_cap) return;
  int n = vm->bytecode->sexp_len[sid];
  ll_expected *arr = vm->bytecode->sexp[sid];
  for (int i = 0; i < n && i < LL_EXPECTED_LIMIT; i++) {
    ll_expected_info_add(&vm->expected, arr[i]);
  }
}

static void ll_vm_new_term_node(ll_vm *vm, int cursor, int offset) {
  if (offset <= 0) return;
  int begin = cursor - offset;
  ll_node_id nid = ll_tree_add_string(&vm->tree, begin, cursor);
  ll_stack_capture_one(&vm->stack, nid);
}

static void ll_vm_new_non_term_node(ll_vm *vm, int cap_id, int cursor, int offset) {
  if (offset <= 0) return;
  int begin = cursor - offset;
  ll_node_id str_node = ll_tree_add_string(&vm->tree, begin, cursor);
  ll_node_id named = ll_tree_add_node(&vm->tree, (int32_t)cap_id, str_node, begin, cursor);
  ll_stack_capture_one(&vm->stack, named);
}

static void ll_vm_new_node(ll_vm *vm, int cursor, ll_frame f, const ll_node_id *nodes, int nodes_len) {
  ll_node_id node_id = -1;
  bool has_node = false;
  bool is_rxp = ll_bitset512_has(&vm->bytecode->rxbs, (int)f.cap_id);
  int32_t cap_id = (int32_t)f.cap_id;
  int start = f.cursor;
  int end = cursor;

  switch (nodes_len) {
  case 0:
    if (cursor - f.cursor > 0) {
      node_id = ll_tree_add_string(&vm->tree, start, end);
      has_node = true;
    } else if (!is_rxp) {
      return;
    }
    break;
  case 1:
    node_id = nodes[0];
    has_node = true;
    break;
  default:
    node_id = ll_tree_add_sequence(&vm->tree, nodes, nodes_len, start, end);
    has_node = true;
    break;
  }

  if (is_rxp) {
    int msg_id = (int)f.cap_id;
    int tmp = 0;
    if (ll_i2i_map_get(&vm->err_labels, (int)f.cap_id, &tmp)) msg_id = tmp;
    ll_node_id err_node;
    if (has_node) {
      err_node = ll_tree_add_error_with_child(&vm->tree, cap_id, (int32_t)msg_id, node_id, start, end);
    } else {
      err_node = ll_tree_add_error(&vm->tree, cap_id, (int32_t)msg_id, start, end);
    }
    ll_stack_capture_one(&vm->stack, err_node);
    return;
  }

  if (!has_node) return;

  if (f.cap_id == 0) {
    ll_stack_capture_one(&vm->stack, node_id);
    return;
  }

  ll_node_id named = ll_tree_add_node(&vm->tree, cap_id, node_id, start, end);
  ll_stack_capture_one(&vm->stack, named);
}

static ll_parsing_error ll_vm_mk_err(ll_vm *vm, const uint8_t *data, int data_len, int err_label_id, int cursor, int err_cursor) {
  bool is_eof = cursor >= data_len;
  uint32_t c = 0;
  if (!is_eof) {
    (void)ll_decode_rune(data, data_len, cursor, &c);
  }

  // Build message (simple dynamic string builder)
  size_t cap = 256, len = 0;
  char *msg = (char *)ll_xrealloc(NULL, cap);
  msg[0] = 0;

  int mapped = 0;
  if (ll_i2i_map_get(&vm->err_labels, err_label_id, &mapped) &&
      mapped >= 0 && mapped < vm->bytecode->strs_len) {
    const char *s = vm->bytecode->strs[mapped];
    size_t sl = strlen(s);
    if (len + sl + 1 > cap) {
      while (len + sl + 1 > cap) cap *= 2;
      msg = (char *)ll_xrealloc(msg, cap);
    }
    memcpy(msg + len, s, sl);
    len += sl;
    msg[len] = 0;
  } else {
    if (err_label_id > 0 && err_label_id < vm->bytecode->strs_len) {
      const char *lab = vm->bytecode->strs[err_label_id];
      size_t need = strlen(lab) + 4;
      if (len + need + 1 > cap) {
        while (len + need + 1 > cap) cap *= 2;
        msg = (char *)ll_xrealloc(msg, cap);
      }
      msg[len++] = '[';
      memcpy(msg + len, lab, strlen(lab));
      len += strlen(lab);
      msg[len++] = ']';
      msg[len++] = ' ';
      msg[len] = 0;
    }

    if (vm->show_fails && vm->expected.cur > 0) {
      const char *pfx = "Expected ";
      size_t pl = strlen(pfx);
      if (len + pl + 1 > cap) { while (len + pl + 1 > cap) cap *= 2; msg = (char *)ll_xrealloc(msg, cap); }
      memcpy(msg + len, pfx, pl); len += pl; msg[len] = 0;

      for (int i = 0; i < vm->expected.cur; i++) {
        ll_expected e = vm->expected.arr[i];
        char buf[64];
        if (e.b != 0) {
          snprintf(buf, sizeof(buf), "'%c-%c'%s", (char)e.a, (char)e.b, (i < vm->expected.cur - 1) ? ", " : "");
        } else {
          snprintf(buf, sizeof(buf), "'%c'%s", (char)e.a, (i < vm->expected.cur - 1) ? ", " : "");
        }
        size_t bl = strlen(buf);
        if (len + bl + 1 > cap) { while (len + bl + 1 > cap) cap *= 2; msg = (char *)ll_xrealloc(msg, cap); }
        memcpy(msg + len, buf, bl); len += bl; msg[len] = 0;
      }

      const char *mid = " but got ";
      size_t ml = strlen(mid);
      if (len + ml + 1 > cap) { while (len + ml + 1 > cap) cap *= 2; msg = (char *)ll_xrealloc(msg, cap); }
      memcpy(msg + len, mid, ml); len += ml; msg[len] = 0;
    } else {
      const char *pfx = "Unexpected ";
      size_t pl = strlen(pfx);
      if (len + pl + 1 > cap) { while (len + pl + 1 > cap) cap *= 2; msg = (char *)ll_xrealloc(msg, cap); }
      memcpy(msg + len, pfx, pl); len += pl; msg[len] = 0;
    }

    if (is_eof) {
      const char *eof = "EOF";
      size_t el = strlen(eof);
      if (len + el + 1 > cap) { while (len + el + 1 > cap) cap *= 2; msg = (char *)ll_xrealloc(msg, cap); }
      memcpy(msg + len, eof, el); len += el; msg[len] = 0;
    } else {
      char buf[16];
      // printable-ish; mirrors Go's single-rune quoting
      if (c <= 0x7F && c != '\'' && c != '\\') {
        snprintf(buf, sizeof(buf), "'%c'", (char)c);
      } else if (c == '\'') {
        snprintf(buf, sizeof(buf), "'\\''");
      } else if (c == '\\') {
        snprintf(buf, sizeof(buf), "'\\\\'");
      } else {
        snprintf(buf, sizeof(buf), "'?'");
      }
      size_t bl = strlen(buf);
      if (len + bl + 1 > cap) { while (len + bl + 1 > cap) cap *= 2; msg = (char *)ll_xrealloc(msg, cap); }
      memcpy(msg + len, buf, bl); len += bl; msg[len] = 0;
    }
  }

  const char *lab = "";
  if (err_label_id > 0 && err_label_id < vm->bytecode->strs_len) {
    lab = vm->bytecode->strs[err_label_id];
  }

  return (ll_parsing_error){
    .message = msg,
    .label = ll_xstrdup(lab),
    .start = cursor,
    .end = err_cursor,
  };
}

ll_tree *ll_vm_match_rule(ll_vm *vm, const uint8_t *data, int data_len, int rule_address, int *out_cursor, ll_parsing_error *out_err) {
  ll_vm_reset(vm);
  ll_tree_bind_input(&vm->tree, data, data_len);
  const uint8_t *code = vm->bytecode->code;
  int ilen = data_len;
  int cursor = 0;
  int pc = 0;

  if (rule_address > 0) {
    ll_stack_push(&vm->stack, ll_mk_call_frame(pc + LL_OP_CALL_SIZE));
    pc = rule_address;
  }

 code_loop:
  for (;;) {
    uint8_t op = code[pc];
    switch (op) {
    case LL_OP_HALT: {
      if (vm->stack.nodes_len > 0) {
        ll_node_id nid = vm->stack.nodes[vm->stack.nodes_len - 1];
        ll_tree_set_root(&vm->tree, nid);
      }
      *out_cursor = cursor;
      if (out_err) memset(out_err, 0, sizeof(*out_err));
      return &vm->tree;
    }
    case LL_OP_ANY: {
      if (cursor >= ilen) goto fail;
      uint32_t r = 0;
      int s = ll_decode_rune(data, ilen, cursor, &r);
      cursor += s;
      pc += LL_OP_ANY_SIZE;
      break;
    }
    case LL_OP_CHAR: {
      uint32_t e = (uint32_t)ll_decode_u16(code, pc + 1);
      if (cursor >= ilen) goto fail;
      uint32_t c = 0;
      int s = ll_decode_rune(data, ilen, cursor, &c);
      if (c != e) {
        if (vm->show_fails) ll_vm_update_expected(vm, cursor, (ll_expected){.a = e, .b = 0});
        goto fail;
      }
      cursor += s;
      pc += LL_OP_CHAR_SIZE;
      break;
    }
    case LL_OP_RANGE: {
      if (cursor >= ilen) goto fail;
      uint32_t c = 0;
      int s = ll_decode_rune(data, ilen, cursor, &c);
      uint32_t a = (uint32_t)ll_decode_u16(code, pc + 1);
      uint32_t b = (uint32_t)ll_decode_u16(code, pc + 3);
      if (c < a || c > b) {
        if (vm->show_fails) ll_vm_update_expected(vm, cursor, (ll_expected){.a = a, .b = b});
        goto fail;
      }
      cursor += s;
      pc += LL_OP_RANGE_SIZE;
      break;
    }
    case LL_OP_SET: {
      if (cursor >= ilen) goto fail;
      uint8_t c = data[cursor];
      uint16_t sid = ll_decode_u16(code, pc + 1);
      if (sid >= (uint16_t)vm->bytecode->sets_len || !ll_charset_has_byte(&vm->bytecode->sets[sid], c)) {
        if (vm->show_fails) ll_vm_update_set_expected(vm, cursor, sid);
        goto fail;
      }
      cursor++;
      pc += LL_OP_SET_SIZE;
      break;
    }
    case LL_OP_SPAN: {
      uint16_t sid = ll_decode_u16(code, pc + 1);
      if (sid < (uint16_t)vm->bytecode->sets_len) {
        ll_charset set = vm->bytecode->sets[sid];
        while (cursor < ilen) {
          uint8_t c = data[cursor];
          if (ll_charset_has_byte(&set, c)) { cursor++; continue; }
          break;
        }
      }
      pc += LL_OP_SPAN_SIZE;
      break;
    }
    case LL_OP_FAIL:
      goto fail;

    case LL_OP_FAIL_TWICE:
      (void)ll_stack_pop(&vm->stack);
      goto fail;

    case LL_OP_CHOICE: {
      int lb = (int)ll_decode_u16(code, pc + 1);
      ll_stack_push(&vm->stack, ll_mk_backtrack_frame(lb, cursor));
      pc += LL_OP_CHOICE_SIZE;
      break;
    }
    case LL_OP_CHOICE_PRED: {
      int lb = (int)ll_decode_u16(code, pc + 1);
      ll_stack_push(&vm->stack, ll_mk_backtrack_pred_frame(lb, cursor));
      pc += LL_OP_CHOICE_SIZE;
      vm->predicate = true;
      break;
    }
    case LL_OP_COMMIT:
      (void)ll_stack_pop(&vm->stack);
      pc = (int)ll_decode_u16(code, pc + 1);
      break;

    case LL_OP_BACK_COMMIT: {
      ll_frame f = ll_stack_pop(&vm->stack);
      cursor = f.cursor;
      pc = (int)ll_decode_u16(code, pc + 1);
      break;
    }

    case LL_OP_PARTIAL_COMMIT:
      pc = (int)ll_decode_u16(code, pc + 1);
      ll_stack_top(&vm->stack)->cursor = cursor;
      break;

    case LL_OP_CALL:
      ll_stack_push(&vm->stack, ll_mk_call_frame(pc + LL_OP_CALL_SIZE));
      pc = (int)ll_decode_u16(code, pc + 1);
      break;

    case LL_OP_RETURN: {
      ll_frame f = ll_stack_pop(&vm->stack);
      pc = (int)f.pc;
      break;
    }

    case LL_OP_JUMP:
      pc = (int)ll_decode_u16(code, pc + 1);
      break;

    case LL_OP_THROW: {
      if (vm->predicate) {
        pc += LL_OP_THROW_SIZE;
        goto fail;
      }
      int lb = (int)ll_decode_u16(code, pc + 1);
      int addr = 0;
      if (ll_i2i_map_get(&vm->bytecode->rxps, lb, &addr)) {
        ll_stack_push(&vm->stack, ll_mk_call_frame(pc + LL_OP_THROW_SIZE));
        pc = addr;
        continue;
      }
      *out_cursor = cursor;
      if (out_err) *out_err = ll_vm_mk_err(vm, data, data_len, lb, cursor, vm->ffp);
      return NULL;
    }

    case LL_OP_CAP_BEGIN: {
      int id = (int)ll_decode_u16(code, pc + 1);
      ll_stack_push(&vm->stack, ll_mk_capture_frame(id, cursor));
      pc += LL_OP_CAP_BEGIN_SIZE;
      break;
    }

    case LL_OP_CAP_END: {
      ll_frame f = ll_stack_pop(&vm->stack);
      int nodes_len = 0;
      const ll_node_id *nodes = ll_stack_frame_nodes(&vm->stack, &f, &nodes_len);
      ll_stack_truncate_arena(&vm->stack, f.nodes_start);
      ll_vm_new_node(vm, cursor, f, nodes, nodes_len);
      pc += LL_OP_CAP_END_SIZE;
      break;
    }

    case LL_OP_CAP_TERM:
      ll_vm_new_term_node(vm, cursor, (int)ll_decode_u16(code, pc + 1));
      pc += LL_OP_CAP_TERM_SIZE;
      break;

    case LL_OP_CAP_NON_TERM: {
      int id = (int)ll_decode_u16(code, pc + 1);
      int offset = (int)ll_decode_u16(code, pc + 3);
      ll_vm_new_non_term_node(vm, id, cursor, offset);
      pc += LL_OP_CAP_NON_TERM_SIZE;
      break;
    }

    case LL_OP_CAP_TERM_BEGIN_OFFSET:
      vm->cap_offset_id = -1;
      vm->cap_offset_start = cursor;
      pc += LL_OP_CAP_TERM_BEGIN_OFFSET_SIZE;
      break;

    case LL_OP_CAP_NON_TERM_BEGIN_OFFSET:
      vm->cap_offset_id = (int)ll_decode_u16(code, pc + 1);
      vm->cap_offset_start = cursor;
      pc += LL_OP_CAP_NON_TERM_BEGIN_OFFSET_SIZE;
      break;

    case LL_OP_CAP_END_OFFSET: {
      int offset = cursor - vm->cap_offset_start;
      pc += LL_OP_CAP_END_OFFSET_SIZE;
      if (vm->cap_offset_id < 0) {
        ll_vm_new_term_node(vm, cursor, offset);
        continue;
      }
      ll_vm_new_non_term_node(vm, vm->cap_offset_id, cursor, offset);
      break;
    }

    case LL_OP_CAP_COMMIT: {
      ll_frame f = ll_stack_pop(&vm->stack);
      ll_stack_commit_captures_to_parent(&vm->stack, f.nodes_start, f.nodes_end);
      pc = (int)ll_decode_u16(code, pc + 1);
      break;
    }

    case LL_OP_CAP_BACK_COMMIT: {
      ll_frame f = ll_stack_pop(&vm->stack);
      ll_stack_commit_captures_to_parent(&vm->stack, f.nodes_start, f.nodes_end);
      cursor = f.cursor;
      pc = (int)ll_decode_u16(code, pc + 1);
      break;
    }

    case LL_OP_CAP_PARTIAL_COMMIT: {
      pc = (int)ll_decode_u16(code, pc + 1);
      ll_frame *top = ll_stack_top(&vm->stack);
      top->cursor = cursor;
      ll_stack_collect_captures(&vm->stack);
      top->nodes_start = (uint32_t)vm->stack.node_arena_len;
      top->nodes_end = top->nodes_start;
      break;
    }

    case LL_OP_CAP_RETURN: {
      ll_frame f = ll_stack_pop(&vm->stack);
      ll_stack_commit_captures_to_parent(&vm->stack, f.nodes_start, f.nodes_end);
      pc = (int)f.pc;
      break;
    }

    default:
      fprintf(stderr, "NO ENTIENDO SENOR: unknown opcode 0x%02x at pc=%d\n", op, pc);
      abort();
    }
  }

 fail:
  if (cursor > vm->ffp) vm->ffp = cursor;
  while (ll_stack_len(&vm->stack) > 0) {
    ll_frame f = ll_stack_pop(&vm->stack);
    ll_stack_truncate_arena(&vm->stack, f.nodes_start);
    if (f.t == LL_FRAME_BACKTRACKING) {
      pc = (int)f.pc;
      vm->predicate = f.predicate;
      cursor = f.cursor;
      goto code_loop;
    }
  }

  *out_cursor = cursor;
  if (out_err) {
    *out_err = ll_vm_mk_err(vm, data, data_len, 0, cursor, vm->ffp);
  }
  return NULL;
}

ll_tree *ll_vm_match(ll_vm *vm, const uint8_t *data, int data_len, int *out_cursor, ll_parsing_error *out_err) {
  return ll_vm_match_rule(vm, data, data_len, 0, out_cursor, out_err);
}

/* ---- END embedded runtime: c/vm.c ---- */

/* ---- BEGIN embedded runtime: c/tree.c ---- */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#ifndef LANGLANG_EMBEDDED
#include "tree.h"
#include "vm.h"
#endif

void *ll_xrealloc(void *p, size_t n);
char *ll_xstrdup(const char *s);

void ll_tree_init(ll_tree *t) {
  memset(t, 0, sizeof(*t));
  t->root = 0;
  t->has_root = false;
}

void ll_tree_free(ll_tree *t) {
  free(t->nodes);
  free(t->children);
  free(t->child_ranges);
  memset(t, 0, sizeof(*t));
}

void ll_tree_reset(ll_tree *t) {
  t->nodes_len = 0;
  t->children_len = 0;
  t->child_ranges_len = 0;
  t->has_root = false;
  t->root = 0;
}

void ll_tree_set_root(ll_tree *t, ll_node_id id) {
  t->root = id;
  t->has_root = true;
}

bool ll_tree_root(const ll_tree *t, ll_node_id *out_id) {
  if (!t->has_root || t->nodes_len == 0) return false;
  *out_id = t->root;
  return true;
}

ll_node_type ll_tree_type(const ll_tree *t, ll_node_id id) {
  return t->nodes[id].typ;
}

const char *ll_tree_name(const ll_tree *t, ll_node_id id) {
  int32_t nid = t->nodes[id].name_id;
  if (nid < 0 || nid >= t->strs_len) return "";
  return t->strs[nid];
}

ll_range ll_tree_range(const ll_tree *t, ll_node_id id) {
  ll_node *n = &t->nodes[id];
  return (ll_range){.start = n->start, .end = n->end};
}

bool ll_tree_child(const ll_tree *t, ll_node_id id, ll_node_id *out_child) {
  const ll_node *n = &t->nodes[id];
  if (n->child_id < 0) return false;
  if (n->typ != LL_NODE_NODE && n->typ != LL_NODE_ERROR) return false;
  *out_child = (ll_node_id)n->child_id;
  return true;
}

int ll_tree_children_len(const ll_tree *t, ll_node_id id) {
  const ll_node *n = &t->nodes[id];
  if (n->typ == LL_NODE_SEQUENCE) {
    if (n->child_id < 0) return 0;
    ll_child_range cr = t->child_ranges[n->child_id];
    return (int)(cr.end - cr.start);
  }
  if (n->typ == LL_NODE_NODE || n->typ == LL_NODE_ERROR) {
    return (n->child_id < 0) ? 0 : 1;
  }
  return 0;
}

bool ll_tree_children_at(const ll_tree *t, ll_node_id id, int idx, ll_node_id *out_child) {
  const ll_node *n = &t->nodes[id];
  if (idx < 0) return false;
  if (n->typ == LL_NODE_SEQUENCE) {
    if (n->child_id < 0) return false;
    ll_child_range cr = t->child_ranges[n->child_id];
    int nchild = (int)(cr.end - cr.start);
    if (idx >= nchild) return false;
    *out_child = t->children[cr.start + idx];
    return true;
  }
  if (n->typ == LL_NODE_NODE || n->typ == LL_NODE_ERROR) {
    if (n->child_id < 0 || idx != 0) return false;
    *out_child = (ll_node_id)n->child_id;
    return true;
  }
  return false;
}

int ll_tree_children(const ll_tree *t, ll_node_id id, ll_node_id *out, int out_cap) {
  int n = ll_tree_children_len(t, id);
  if (!out || out_cap <= 0) return n;
  int m = n < out_cap ? n : out_cap;
  for (int i = 0; i < m; i++) {
    ll_node_id child = 0;
    if (!ll_tree_children_at(t, id, i, &child)) break;
    out[i] = child;
  }
  return n;
}

char *ll_tree_text(const ll_tree *t, ll_node_id id) {
  const ll_node *n = &t->nodes[id];
  switch (n->typ) {
  case LL_NODE_STRING: {
    int start = n->start, end = n->end;
    if (start < 0) start = 0;
    if (end > t->input_len) end = t->input_len;
    if (end < start) end = start;
    int len = end - start;
    char *out = (char *)ll_xrealloc(NULL, (size_t)len + 1);
    memcpy(out, t->input + start, (size_t)len);
    out[len] = 0;
    return out;
  }
  case LL_NODE_SEQUENCE: {
    if (n->child_id < 0) return ll_xstrdup("");
    ll_child_range cr = t->child_ranges[n->child_id];
    // naive O(total) concatenation
    size_t cap = 64, cur = 0;
    char *buf = (char *)ll_xrealloc(NULL, cap);
    buf[0] = 0;
    for (int32_t i = cr.start; i < cr.end; i++) {
      char *part = ll_tree_text(t, t->children[i]);
      size_t plen = strlen(part);
      if (cur + plen + 1 > cap) {
        while (cur + plen + 1 > cap) cap *= 2;
        buf = (char *)ll_xrealloc(buf, cap);
      }
      memcpy(buf + cur, part, plen);
      cur += plen;
      buf[cur] = 0;
      free(part);
    }
    return buf;
  }
  case LL_NODE_NODE:
  case LL_NODE_ERROR: {
    if (n->child_id < 0) {
      if (n->typ == LL_NODE_ERROR) {
        // mimic Go: "error[<label>]"
        const char *label = ll_tree_name(t, id);
        size_t need = strlen("error[]") + strlen(label) + 1;
        char *out = (char *)ll_xrealloc(NULL, need);
        snprintf(out, need, "error[%s]", label);
        return out;
      }
      return ll_xstrdup("");
    }
    return ll_tree_text(t, (ll_node_id)n->child_id);
  }
  default:
    return ll_xstrdup("");
  }
}

static void ll_pretty_ensure(char **out, size_t *len, size_t *cap, size_t add) {
  if (*len + add + 1 <= *cap) return;
  while (*len + add + 1 > *cap) *cap *= 2;
  *out = (char *)ll_xrealloc(*out, *cap);
}

static void ll_pretty_append_n(char **out, size_t *len, size_t *cap, const char *s, size_t n) {
  ll_pretty_ensure(out, len, cap, n);
  memcpy(*out + *len, s, n);
  *len += n;
  (*out)[*len] = 0;
}

static void ll_pretty_append(char **out, size_t *len, size_t *cap, const char *s) {
  ll_pretty_append_n(out, len, cap, s, strlen(s));
}

static void ll_pretty_append_ch(char **out, size_t *len, size_t *cap, char c) {
  ll_pretty_ensure(out, len, cap, 1);
  (*out)[(*len)++] = c;
  (*out)[*len] = 0;
}

static void ll_pretty_append_quoted_slice(char **out, size_t *len, size_t *cap, const uint8_t *buf, int start, int end) {
  ll_pretty_append_ch(out, len, cap, '"');
  for (int i = start; i < end; i++) {
    uint8_t c = buf[i];
    if (c == '\\' || c == '"') {
      ll_pretty_append_ch(out, len, cap, '\\');
      ll_pretty_append_ch(out, len, cap, (char)c);
    } else if (c == '\n') {
      ll_pretty_append_ch(out, len, cap, '\\');
      ll_pretty_append_ch(out, len, cap, 'n');
    } else if (c == '\r') {
      ll_pretty_append_ch(out, len, cap, '\\');
      ll_pretty_append_ch(out, len, cap, 'r');
    } else if (c == '\t') {
      ll_pretty_append_ch(out, len, cap, '\\');
      ll_pretty_append_ch(out, len, cap, 't');
    } else {
      ll_pretty_append_ch(out, len, cap, (char)c);
    }
  }
  ll_pretty_append_ch(out, len, cap, '"');
}

static void ll_tree_pretty_rec(const ll_tree *t,
                               ll_node_id id,
                               char **out,
                               size_t *len,
                               size_t *cap,
                               const char *prefix,
                               bool is_last,
                               bool is_root) {
  const ll_node *n = &t->nodes[id];

  // Prefix + branch connectors (Unicode box-drawing, like the Go pretty-printer).
  if (prefix && prefix[0]) ll_pretty_append(out, len, cap, prefix);
  if (!is_root) {
    ll_pretty_append(out, len, cap, is_last ? "└── " : "├── ");
  }

  // Render node label.
  if (n->typ == LL_NODE_STRING) {
    int start = n->start, end = n->end;
    start = start < 0 ? 0 : start;
    end = end > t->input_len ? t->input_len : end;
    if (end < start) end = start;
    ll_pretty_append_quoted_slice(out, len, cap, t->input, start, end);
    ll_pretty_append_ch(out, len, cap, '\n');
    return;
  }

  if (n->typ == LL_NODE_SEQUENCE) {
    char buf[64];
    int wrote = snprintf(buf, sizeof(buf), "Sequence (%d..%d)", n->start, n->end);
    if (wrote < 0) wrote = 0;
    ll_pretty_append_n(out, len, cap, buf, (size_t)wrote);
    ll_pretty_append_ch(out, len, cap, '\n');
  } else if (n->typ == LL_NODE_NODE) {
    const char *name = ll_tree_name(t, id);
    // write: "<name> (start..end)\n"
    ll_pretty_append(out, len, cap, name);
    char buf[48];
    int wrote = snprintf(buf, sizeof(buf), " (%d..%d)", n->start, n->end);
    if (wrote < 0) wrote = 0;
    ll_pretty_append_n(out, len, cap, buf, (size_t)wrote);
    ll_pretty_append_ch(out, len, cap, '\n');
  } else if (n->typ == LL_NODE_ERROR) {
    const char *label = ll_tree_name(t, id);
    ll_pretty_append(out, len, cap, "Error<");
    ll_pretty_append(out, len, cap, label);
    ll_pretty_append(out, len, cap, ">");
    char buf[48];
    int wrote = snprintf(buf, sizeof(buf), " (%d..%d)", n->start, n->end);
    if (wrote < 0) wrote = 0;
    ll_pretty_append_n(out, len, cap, buf, (size_t)wrote);
    ll_pretty_append_ch(out, len, cap, '\n');
  } else {
    ll_pretty_append(out, len, cap, "(unknown)\n");
    return;
  }

  // Recurse
  const char *pad = "";
  if (!is_root) pad = is_last ? "    " : "│   ";

  size_t plen = prefix ? strlen(prefix) : 0;
  size_t padlen = strlen(pad);
  char *next_prefix = NULL;
  if (plen + padlen > 0) {
    next_prefix = (char *)ll_xrealloc(NULL, plen + padlen + 1);
    if (plen) memcpy(next_prefix, prefix, plen);
    if (padlen) memcpy(next_prefix + plen, pad, padlen);
    next_prefix[plen + padlen] = 0;
  }

  const char *np = next_prefix ? next_prefix : "";

  if (n->typ == LL_NODE_SEQUENCE && n->child_id >= 0) {
    ll_child_range cr = t->child_ranges[n->child_id];
    for (int32_t i = cr.start; i < cr.end; i++) {
      bool child_last = (i == cr.end - 1);
      ll_tree_pretty_rec(t, t->children[i], out, len, cap, np, child_last, false);
    }
  } else if ((n->typ == LL_NODE_NODE || n->typ == LL_NODE_ERROR) && n->child_id >= 0) {
    ll_tree_pretty_rec(t, (ll_node_id)n->child_id, out, len, cap, np, true, false);
  }

  free(next_prefix);
}

char *ll_tree_pretty(const ll_tree *t, ll_node_id id) {
  size_t cap = 1024, len = 0;
  char *out = (char *)ll_xrealloc(NULL, cap);
  out[0] = 0;
  ll_tree_pretty_rec(t, id, &out, &len, &cap, "", true, true);
  out[len] = 0;
  return out;
}

char *ll_tree_highlight(const ll_tree *t, ll_node_id id) {
  // TODO: add ANSI colors (like Go's tree.Highlight). For now, Pretty() already
  // prints the full structure with Unicode connectors.
  return ll_tree_pretty(t, id);
}

ll_tree *ll_tree_copy(const ll_tree *t) {
  if (!t) return NULL;
  ll_tree *out = (ll_tree *)ll_xrealloc(NULL, sizeof(ll_tree));
  memset(out, 0, sizeof(*out));

  out->nodes_len = t->nodes_len;
  out->nodes_cap = t->nodes_len;
  if (t->nodes_len > 0) {
    out->nodes = (ll_node *)ll_xrealloc(NULL, (size_t)t->nodes_len * sizeof(ll_node));
    memcpy(out->nodes, t->nodes, (size_t)t->nodes_len * sizeof(ll_node));
  }

  out->children_len = t->children_len;
  out->children_cap = t->children_len;
  if (t->children_len > 0) {
    out->children = (ll_node_id *)ll_xrealloc(NULL, (size_t)t->children_len * sizeof(ll_node_id));
    memcpy(out->children, t->children, (size_t)t->children_len * sizeof(ll_node_id));
  }

  out->child_ranges_len = t->child_ranges_len;
  out->child_ranges_cap = t->child_ranges_len;
  if (t->child_ranges_len > 0) {
    out->child_ranges = (ll_child_range *)ll_xrealloc(NULL, (size_t)t->child_ranges_len * sizeof(ll_child_range));
    memcpy(out->child_ranges, t->child_ranges, (size_t)t->child_ranges_len * sizeof(ll_child_range));
  }

  // Borrowed fields (match Go Tree.Copy docs)
  out->strs = t->strs;
  out->strs_len = t->strs_len;
  out->input = t->input;
  out->input_len = t->input_len;

  out->root = t->root;
  out->has_root = t->has_root;
  return out;
}

void ll_tree_destroy(ll_tree *t) {
  if (!t) return;
  ll_tree_free(t);
  free(t);
}

/* internal utilities */

void ll_tree_bind_input(ll_tree *t, const uint8_t *input, int input_len) {
  t->input = input;
  t->input_len = input_len;
}

void ll_tree_bind_strings(ll_tree *t, const char **strs, int strs_len) {
  t->strs = strs;
  t->strs_len = strs_len;
}

static void _ll_tree_grow_nodes(ll_tree *t, int need) {
  if (t->nodes_len + need <= t->nodes_cap) return;
  int cap = t->nodes_cap ? t->nodes_cap : 256;
  while (cap < t->nodes_len + need) cap *= 2;
  t->nodes = (ll_node *)ll_xrealloc(t->nodes, (size_t)cap * sizeof(ll_node));
  t->nodes_cap = cap;
}

static void _ll_tree_grow_children(ll_tree *t, int need) {
  if (t->children_len + need <= t->children_cap) return;
  int cap = t->children_cap ? t->children_cap : 512;
  while (cap < t->children_len + need) cap *= 2;
  t->children = (ll_node_id *)ll_xrealloc(t->children, (size_t)cap * sizeof(ll_node_id));
  t->children_cap = cap;
}

static void _ll_tree_grow_child_ranges(ll_tree *t, int need) {
  if (t->child_ranges_len + need <= t->child_ranges_cap) return;
  int cap = t->child_ranges_cap ? t->child_ranges_cap : 256;
  while (cap < t->child_ranges_len + need) cap *= 2;
  t->child_ranges = (ll_child_range *)ll_xrealloc(t->child_ranges, (size_t)cap * sizeof(ll_child_range));
  t->child_ranges_cap = cap;
}

/* utilities used by the VM */

ll_node_id ll_tree_add_string(ll_tree *t, int start, int end) {
  _ll_tree_grow_nodes(t, 1);
  ll_node_id id = (ll_node_id)t->nodes_len;
  t->nodes[t->nodes_len++] = (ll_node){
    .typ = LL_NODE_STRING,
    .start = start,
    .end = end,
    .name_id = -1,
    .child_id = -1,
    .message_id = -1,
  };
  return id;
}

ll_node_id ll_tree_add_sequence(ll_tree *t, const ll_node_id *children, int children_len, int start, int end) {
  _ll_tree_grow_nodes(t, 1);
  int32_t child_range_id = -1;
  if (children_len > 0) {
    _ll_tree_grow_child_ranges(t, 1);
    child_range_id = (int32_t)t->child_ranges_len;
    int32_t child_start = (int32_t)t->children_len;
    _ll_tree_grow_children(t, children_len);
    memcpy(&t->children[t->children_len], children, (size_t)children_len * sizeof(ll_node_id));
    t->children_len += children_len;
    int32_t child_end = (int32_t)t->children_len;
    t->child_ranges[t->child_ranges_len++] = (ll_child_range){.start = child_start, .end = child_end};
  }
  ll_node_id id = (ll_node_id)t->nodes_len;
  t->nodes[t->nodes_len++] = (ll_node){
    .typ = LL_NODE_SEQUENCE,
    .start = start,
    .end = end,
    .name_id = -1,
    .child_id = child_range_id,
    .message_id = -1,
  };
  return id;
}

ll_node_id ll_tree_add_node(ll_tree *t, int32_t name_id, ll_node_id child, int start, int end) {
  _ll_tree_grow_nodes(t, 1);
  ll_node_id id = (ll_node_id)t->nodes_len;
  t->nodes[t->nodes_len++] = (ll_node){
    .typ = LL_NODE_NODE,
    .start = start,
    .end = end,
    .name_id = name_id,
    .child_id = (int32_t)child,
    .message_id = -1,
  };
  return id;
}

ll_node_id ll_tree_add_error(ll_tree *t,
                             int32_t label_id,
                             int32_t message_id,
                             int start,
                             int end)
{
  _ll_tree_grow_nodes(t, 1);
  ll_node_id id = (ll_node_id)t->nodes_len;
  t->nodes[t->nodes_len++] = (ll_node){
    .typ = LL_NODE_ERROR,
    .start = start,
    .end = end,
    .name_id = label_id,
    .child_id = -1,
    .message_id = message_id,
  };
  return id;
}

ll_node_id ll_tree_add_error_with_child(ll_tree *t,
                                        int32_t label_id,
                                        int32_t message_id,
                                        ll_node_id child_id,
                                        int start,
                                        int end)
{
  _ll_tree_grow_nodes(t, 1);
  ll_node_id id = (ll_node_id)t->nodes_len;
  t->nodes[t->nodes_len++] = (ll_node){
    .typ = LL_NODE_ERROR,
    .start = start,
    .end = end,
    .name_id = label_id,
    .child_id = (int32_t)child_id,
    .message_id = message_id,
  };
  return id;
}

/* ---- END embedded runtime: c/tree.c ---- */

/* ---- BEGIN generated parser ---- */

/* Bytecode for generated parser */
static const uint8_t Parser_bytecode_code[] = {
  11, 5, 0, 0, 0, 15, 1, 0, 6, 231, 0, 18, 0, 0, 6, 33, 0, 26, 3, 0, 2, 47, 0, 2, 
  47, 0, 18, 1, 0, 27, 8, 228, 0, 6, 103, 0, 15, 4, 0, 18, 0, 0, 2, 105, 0, 2, 109, 0, 
  2, 112, 0, 2, 111, 0, 2, 114, 0, 2, 116, 0, 19, 6, 0, 18, 0, 0, 26, 6, 0, 17, 2, 0, 
  18, 3, 0, 27, 18, 0, 0, 17, 4, 0, 19, 1, 0, 25, 18, 5, 0, 27, 18, 0, 0, 17, 4, 0, 
  19, 1, 0, 16, 8, 228, 0, 6, 198, 0, 15, 7, 0, 6, 139, 0, 11, 252, 0, 0, 18, 0, 0, 26, 
  6, 0, 17, 2, 0, 18, 3, 0, 27, 18, 0, 0, 11, 10, 2, 0, 8, 194, 0, 11, 252, 0, 0, 18, 
  0, 0, 15, 10, 0, 18, 0, 0, 26, 6, 0, 17, 2, 0, 18, 3, 0, 27, 6, 193, 0, 18, 0, 0, 
  18, 0, 0, 17, 6, 0, 19, 1, 0, 18, 0, 0, 26, 6, 0, 17, 2, 0, 18, 3, 0, 27, 9, 165, 
  0, 16, 16, 8, 228, 0, 15, 11, 0, 18, 0, 0, 11, 188, 1, 0, 18, 0, 0, 2, 60, 0, 2, 62, 
  0, 19, 2, 0, 18, 0, 0, 11, 188, 1, 0, 16, 9, 11, 0, 16, 12, 15, 13, 0, 18, 0, 0, 11, 
  252, 0, 0, 18, 0, 0, 11, 10, 2, 0, 16, 12, 15, 8, 0, 6, 23, 1, 2, 105, 0, 2, 110, 0, 
  2, 112, 0, 2, 117, 0, 2, 116, 0, 19, 5, 0, 8, 186, 1, 6, 50, 1, 2, 111, 0, 2, 117, 0, 
  2, 116, 0, 2, 112, 0, 2, 117, 0, 2, 116, 0, 19, 6, 0, 8, 186, 1, 6, 68, 1, 2, 98, 0, 
  2, 117, 0, 2, 115, 0, 19, 3, 0, 8, 186, 1, 6, 86, 1, 2, 108, 0, 2, 101, 0, 2, 100, 0, 
  19, 3, 0, 8, 186, 1, 6, 104, 1, 2, 97, 0, 2, 110, 0, 2, 100, 0, 19, 3, 0, 8, 186, 1, 
  6, 119, 1, 2, 111, 0, 2, 114, 0, 19, 2, 0, 8, 186, 1, 6, 137, 1, 2, 110, 0, 2, 111, 0, 
  2, 116, 0, 19, 3, 0, 8, 186, 1, 6, 155, 1, 2, 120, 0, 2, 111, 0, 2, 114, 0, 19, 3, 0, 
  8, 186, 1, 6, 176, 1, 2, 110, 0, 2, 97, 0, 2, 110, 0, 2, 100, 0, 19, 4, 0, 8, 186, 1, 
  26, 6, 0, 17, 2, 0, 18, 3, 0, 27, 16, 12, 15, 12, 0, 6, 223, 1, 11, 233, 0, 0, 18, 0, 
  0, 17, 7, 0, 19, 1, 0, 18, 0, 0, 26, 6, 0, 17, 2, 0, 18, 3, 0, 27, 8, 8, 2, 26, 
  6, 0, 17, 2, 0, 18, 3, 0, 27, 18, 0, 0, 6, 8, 2, 18, 0, 0, 17, 7, 0, 19, 1, 0, 
  18, 0, 0, 26, 6, 0, 17, 2, 0, 18, 3, 0, 27, 8, 8, 2, 16, 12, 15, 9, 0, 18, 0, 0, 
  17, 8, 0, 19, 1, 0, 18, 0, 0, 26, 6, 0, 17, 2, 0, 18, 3, 0, 27, 18, 0, 0, 17, 9, 
  0, 19, 1, 0, 18, 0, 0, 11, 188, 1, 0, 6, 98, 2, 18, 0, 0, 18, 0, 0, 17, 6, 0, 19, 
  1, 0, 18, 0, 0, 26, 6, 0, 17, 2, 0, 18, 3, 0, 27, 18, 0, 0, 17, 9, 0, 19, 1, 0, 
  18, 0, 0, 11, 188, 1, 0, 9, 54, 2, 18, 0, 0, 17, 10, 0, 19, 1, 0, 16, 12, 
};

static const char *Parser_bytecode_strs[] = {
  "",
  "Program",
  "Spacing",
  "Annotation",
  "ImportDecl",
  "",
  "Identifier",
  "Declaration",
  "ComponentType",
  "BusType",
  "IdentList",
  "Connection",
  "PortRef",
  "AnonDecl",
  "Space",
  "EOL",
  "EOF",
};

static const ll_charset Parser_bytecode_sets[] = {
  { .bits = {0,38,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,} },
  { .bits = {255,251,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,} },
  { .bits = {0,0,0,0,0,0,0,0,254,255,255,135,254,255,255,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,} },
  { .bits = {0,0,0,0,0,0,255,3,254,255,255,135,254,255,255,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,} },
  { .bits = {0,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,} },
  { .bits = {255,255,255,255,251,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,} },
  { .bits = {0,0,0,0,0,16,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,} },
  { .bits = {0,0,0,0,0,64,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,} },
  { .bits = {0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,} },
  { .bits = {0,0,0,0,0,0,0,32,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,} },
  { .bits = {0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,} },
};

static const ll_bytecode Parser_bytecode = {
  .code = (uint8_t *)&Parser_bytecode_code,
  .code_len = 621,
  .strs = (const char **)&Parser_bytecode_strs,
  .strs_len = 17,
  .sets = (ll_charset *)&Parser_bytecode_sets,
  .sets_len = 11,
};

static void init_bytecode_for_Parser(ll_bytecode *bc) {
  /* Recovery Expressions Map */

  /* Recovery Expressions Bitset */
  bc->rxbs.w[0] = (uint64_t)0;
  bc->rxbs.w[1] = (uint64_t)0;
  bc->rxbs.w[2] = (uint64_t)0;
  bc->rxbs.w[3] = (uint64_t)0;
  bc->rxbs.w[4] = (uint64_t)0;
  bc->rxbs.w[5] = (uint64_t)0;
  bc->rxbs.w[6] = (uint64_t)0;
  bc->rxbs.w[7] = (uint64_t)0;

  /* strings map (smap) */
  ll_s2i_map_put(&bc->smap, "", 5);
  ll_s2i_map_put(&bc->smap, "Annotation", 3);
  ll_s2i_map_put(&bc->smap, "AnonDecl", 13);
  ll_s2i_map_put(&bc->smap, "BusType", 9);
  ll_s2i_map_put(&bc->smap, "ComponentType", 8);
  ll_s2i_map_put(&bc->smap, "Connection", 11);
  ll_s2i_map_put(&bc->smap, "Declaration", 7);
  ll_s2i_map_put(&bc->smap, "EOF", 16);
  ll_s2i_map_put(&bc->smap, "EOL", 15);
  ll_s2i_map_put(&bc->smap, "IdentList", 10);
  ll_s2i_map_put(&bc->smap, "Identifier", 6);
  ll_s2i_map_put(&bc->smap, "ImportDecl", 4);
  ll_s2i_map_put(&bc->smap, "PortRef", 12);
  ll_s2i_map_put(&bc->smap, "Program", 1);
  ll_s2i_map_put(&bc->smap, "Space", 14);
  ll_s2i_map_put(&bc->smap, "Spacing", 2);

  /* Precompute expected sets for show-fails. */
  //ll_bytecode_build_expected_sets(bc);
}

struct Parser {
  const uint8_t *input;
  int input_len;
  ll_bytecode bc;
  ll_vm vm;
};
typedef struct Parser Parser;

void Parser_SetInput(Parser *p, const uint8_t *input, int input_len) {
  p->input = input;
  p->input_len = input_len;
}

void Parser_Init(Parser *p) {
  ll_bytecode *bc = (ll_bytecode *)malloc(sizeof(Parser_bytecode));;
  memcpy(bc, (ll_bytecode*)&Parser_bytecode, sizeof(Parser_bytecode));
  init_bytecode_for_Parser(bc);
  memset(p, 0, sizeof(*p));
  ll_vm_init(&p->vm, bc);
}

void Parser_Free(Parser *p) {
  ll_vm_free(&p->vm);
  ll_bytecode_free(&p->bc);
}

void Parser_SetShowFails(Parser *p, bool v) {
  ll_vm_set_show_fails(&p->vm, v);
}

Parser *Parser_New(void) {
  Parser *p = (Parser *)malloc(sizeof(Parser));
  if (!p) { fprintf(stderr, "out of memory\n"); abort(); }
  Parser_Init(p);
  return p;
}

void Parser_Delete(Parser *p) {
  if (!p) return;
  Parser_Free(p);
  free(p);
}

static ll_tree *Parser_parse_fn(Parser *p, int addr, int *out_cursor, ll_parsing_error *out_err) {
  return ll_vm_match_rule(&p->vm, p->input, p->input_len, addr, out_cursor, out_err);
}

ll_tree *Parser_ParseProgram(Parser *p, int *out_cursor, ll_parsing_error *out_err) {
  return Parser_parse_fn(p, 5, out_cursor, out_err);
}
ll_tree *Parser_ParseAnonDecl(Parser *p, int *out_cursor, ll_parsing_error *out_err) {
  return Parser_parse_fn(p, 233, out_cursor, out_err);
}
ll_tree *Parser_ParseComponentType(Parser *p, int *out_cursor, ll_parsing_error *out_err) {
  return Parser_parse_fn(p, 252, out_cursor, out_err);
}
ll_tree *Parser_ParsePortRef(Parser *p, int *out_cursor, ll_parsing_error *out_err) {
  return Parser_parse_fn(p, 444, out_cursor, out_err);
}
ll_tree *Parser_ParseBusType(Parser *p, int *out_cursor, ll_parsing_error *out_err) {
  return Parser_parse_fn(p, 522, out_cursor, out_err);
}

ll_tree *Parser_Parse(Parser *p, int *out_cursor, ll_parsing_error *out_err) {
  return Parser_parse_fn(p, 5, out_cursor, out_err);
}

