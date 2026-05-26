// Package main exposes the langlang parser as a C-callable surface for
// go build -buildmode=c-archive. main() is empty; the archive is linked
// into circ-compile by Zig.
package main

/*
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
*/
import "C"

import (
	"runtime/cgo"
	"unsafe"

	"circ-compiler/parser"
)

type handle struct {
	tree parser.Tree

	// Borrowed pointer to the source buffer; the caller (Zig) owns the
	// buffer's lifetime and must keep it alive until ParserDelete.
	sourcePtr *C.char
	sourceLen C.int

	// Stable C-string cache so Zig can compare returned name pointers
	// across calls. Keyed by string identity (not NodeID) because the
	// same name (e.g. "Identifier") appears on many nodes.
	nameCache map[string]*C.char

	// Last parse error captured on a failed Parse, exposed to Zig via the
	// ParserError* accessors. errMsg is an owned C string freed on delete.
	errStart C.int
	errEnd   C.int
	errMsg   *C.char
}

//export ParserNew
func ParserNew() C.uintptr_t {
	h := &handle{nameCache: make(map[string]*C.char)}
	return C.uintptr_t(cgo.NewHandle(h))
}

// circLabelMessages maps the grammar's failure labels (proto-circ.peg) to
// human-readable diagnostics. Attached to every parser so a thrown label
// carries its message on the ParsingError.
var circLabelMessages = map[string]string{
	"trailing":  "unexpected input; expected a declaration, input, output, or import",
	"busname":   "expected a port name",
	"busassign": "expected '=' after the port name",
	"busvalue":  "expected a signal reference after '='",
	"busclose":  "expected ')' to close the connection list",
}

//export ParserParse
func ParserParse(hid C.uintptr_t, source *C.char, length C.int) C.bool {
	h := cgo.Handle(hid).Value().(*handle)
	src := unsafe.Slice((*byte)(unsafe.Pointer(source)), int(length))
	p := parser.NewParser()
	p.SetLabelMessages(parser.LabelMessagesForParser(circLabelMessages))
	p.SetInput(src)
	tree, err := p.Parse()
	if err != nil {
		h.errStart, h.errEnd = 0, 0
		var msg string
		switch pe := err.(type) {
		case parser.ParsingError:
			h.errStart, h.errEnd = C.int(pe.Start), C.int(pe.End)
			msg = pe.Message
			if msg == "" {
				msg = pe.Error()
			}
		case *parser.ParsingError:
			h.errStart, h.errEnd = C.int(pe.Start), C.int(pe.End)
			msg = pe.Message
			if msg == "" {
				msg = pe.Error()
			}
		default:
			msg = err.Error()
		}
		if h.errMsg != nil {
			C.free(unsafe.Pointer(h.errMsg))
		}
		h.errMsg = C.CString(msg)
		return false
	}
	h.tree = tree
	h.sourcePtr = source
	h.sourceLen = length
	return true
}

//export ParserErrorStart
func ParserErrorStart(hid C.uintptr_t) C.int {
	return cgo.Handle(hid).Value().(*handle).errStart
}

//export ParserErrorEnd
func ParserErrorEnd(hid C.uintptr_t) C.int {
	return cgo.Handle(hid).Value().(*handle).errEnd
}

//export ParserErrorMessage
func ParserErrorMessage(hid C.uintptr_t) *C.char {
	return cgo.Handle(hid).Value().(*handle).errMsg
}

//export ParserDelete
func ParserDelete(hid C.uintptr_t) {
	h := cgo.Handle(hid).Value().(*handle)
	for _, p := range h.nameCache {
		C.free(unsafe.Pointer(p))
	}
	if h.errMsg != nil {
		C.free(unsafe.Pointer(h.errMsg))
	}
	cgo.Handle(hid).Delete()
}

//export TreeRoot
func TreeRoot(hid C.uintptr_t, out *C.uint32_t) C.bool {
	h := cgo.Handle(hid).Value().(*handle)
	id, ok := h.tree.Root()
	if !ok {
		return false
	}
	*out = C.uint32_t(id)
	return true
}

//export TreeType
func TreeType(hid C.uintptr_t, id C.uint32_t) C.uint8_t {
	h := cgo.Handle(hid).Value().(*handle)
	return C.uint8_t(h.tree.Type(parser.NodeID(id)))
}

//export TreeName
func TreeName(hid C.uintptr_t, id C.uint32_t) *C.char {
	h := cgo.Handle(hid).Value().(*handle)
	name := h.tree.Name(parser.NodeID(id))
	if cached, ok := h.nameCache[name]; ok {
		return cached
	}
	cstr := C.CString(name)
	h.nameCache[name] = cstr
	return cstr
}

//export TreeSpanStart
func TreeSpanStart(hid C.uintptr_t, id C.uint32_t) C.int {
	h := cgo.Handle(hid).Value().(*handle)
	return C.int(h.tree.Span(parser.NodeID(id)).Start.Cursor)
}

//export TreeSpanEnd
func TreeSpanEnd(hid C.uintptr_t, id C.uint32_t) C.int {
	h := cgo.Handle(hid).Value().(*handle)
	return C.int(h.tree.Span(parser.NodeID(id)).End.Cursor)
}

//export TreeChild
func TreeChild(hid C.uintptr_t, id C.uint32_t, out *C.uint32_t) C.bool {
	h := cgo.Handle(hid).Value().(*handle)
	child, ok := h.tree.Child(parser.NodeID(id))
	if !ok {
		return false
	}
	*out = C.uint32_t(child)
	return true
}

//export TreeChildrenLen
func TreeChildrenLen(hid C.uintptr_t, id C.uint32_t) C.int {
	h := cgo.Handle(hid).Value().(*handle)
	return C.int(len(h.tree.Children(parser.NodeID(id))))
}

//export TreeChildrenAt
func TreeChildrenAt(hid C.uintptr_t, id C.uint32_t, idx C.int, out *C.uint32_t) C.bool {
	h := cgo.Handle(hid).Value().(*handle)
	children := h.tree.Children(parser.NodeID(id))
	if int(idx) < 0 || int(idx) >= len(children) {
		return false
	}
	*out = C.uint32_t(children[idx])
	return true
}

//export TreeInput
func TreeInput(hid C.uintptr_t, outLen *C.int) *C.char {
	h := cgo.Handle(hid).Value().(*handle)
	*outLen = h.sourceLen
	return h.sourcePtr
}

func main() {}
