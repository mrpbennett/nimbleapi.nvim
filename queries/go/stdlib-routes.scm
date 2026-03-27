;; stdlib route registration patterns for Go net/http
;; Source: tree-sitter-go grammar field names (verified against grammar.js)
;; Capture names follow nimbleapi.nvim convention:
;;   @route_path, @func_name, @route_def
;;   @_receiver is internal (prefixed _) — receiver identity does not matter for route output
;;   @http_method captures "HandleFunc" or "Handle" — method extracted from route_path at runtime
;;
;; Method is NOT extracted from @http_method (it's always "Handle" or "HandleFunc").
;; Instead, method is derived Lua-side from the route_path string:
;;   - Pre-1.22:  "/path"       -> method = ANY
;;   - Go 1.22+:  "GET /path"   -> method = GET, path = /path

;; Pattern 1: receiver.HandleFunc/Handle with simple identifier receiver
;; Covers: mux.HandleFunc, http.HandleFunc, router.Handle, srv.Handle, etc.
;; NOTE: http.HandleFunc is captured here because "http" is just an identifier name;
;; no special-casing needed — the query treats all identifier receivers equally.
(call_expression
  function: (selector_expression
    operand: (identifier) @_receiver
    field: (field_identifier) @http_method
    (#match? @http_method "^Handle"))
  arguments: (argument_list
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def

;; Pattern 2: selector_expression receiver — struct field chain (s.mux.HandleFunc, etc.)
;; Covers: s.mux.HandleFunc, srv.router.Handle, app.mux.HandleFunc, etc.
;; The operand of the outer selector_expression is itself a selector_expression (not identifier).
;; This pattern does NOT capture identifier receivers (handled by Pattern 1 above).
(call_expression
  function: (selector_expression
    operand: (selector_expression)
    field: (field_identifier) @http_method
    (#match? @http_method "^Handle"))
  arguments: (argument_list
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def
