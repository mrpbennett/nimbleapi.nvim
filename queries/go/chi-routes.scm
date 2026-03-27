;; Chi route registration and sub-router container patterns for Go
;; Source: tree-sitter-go grammar field names (verified from grammar.js)
;; Capture names follow nimbleapi.nvim convention:
;;   @router_obj, @http_method, @route_path, @func_name, @route_def
;;
;; Chi uses mixed-case method names (Get, Post, Put, etc.) unlike Gin (GET, POST).
;; Route and Group are captured but NOT emitted as route entries — Lua skips them.
;; The @route_def node on Route/Group calls enables parent-chain prefix resolution (CHI-05).

;; Pattern 1: All r.METHOD("/path", handler) calls
;; Covers: Get/Post/Put/Delete/Patch/Options/Head/Connect/Trace (leaf routes)
;;         Handle/HandleFunc (-> ANY, CHI-03)
;;         Mount (-> MOUNT, CHI-06)
;;         Route/Group (prefix/middleware containers — Lua skips emitting, uses for parent-chain walk, CHI-05/CHI-07)
(call_expression
  function: (selector_expression
    operand: (identifier) @router_obj
    field: (field_identifier) @http_method)
  arguments: (argument_list
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def

;; Pattern 2: r.Method("GET", "/path", handler) and r.MethodFunc("POST", "/path", fn)
;; @_method_arg captures the first string argument (the HTTP method)
;; @http_method captures "Method" or "MethodFunc" — Lua reads @_method_arg when this matches
;; Uses #match? with "^Method" to catch both Method and MethodFunc in one pattern (CHI-04)
(call_expression
  function: (selector_expression
    operand: (identifier) @router_obj
    field: (field_identifier) @http_method
    (#match? @http_method "^Method"))
  arguments: (argument_list
    (interpreted_string_literal) @_method_arg
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def
