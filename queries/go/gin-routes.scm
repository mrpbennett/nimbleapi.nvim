;; Gin route registration patterns for Go
;; Source: tree-sitter-go grammar field names (verified against grammar.js)
;; Capture names follow nimbleapi.nvim convention:
;;   @router_obj, @http_method, @route_path, @func_name, @route_def

;; Pattern 1: Method shortcuts — router.GET("/path", handler), router.POST(...), etc.
;; Also matches router.Any("/path", handler) — Lua side filters by GIN_METHODS table
(call_expression
  function: (selector_expression
    operand: (identifier) @router_obj
    field: (field_identifier) @http_method)
  arguments: (argument_list
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def

;; Pattern 2: Handle — router.Handle("GET", "/path", handler)
;; @_handle_method captures the first string arg (the HTTP method)
;; @http_method captures "Handle" — Lua side checks this to switch to @_handle_method
(call_expression
  function: (selector_expression
    operand: (identifier) @router_obj
    field: (field_identifier) @http_method
    (#eq? @http_method "Handle"))
  arguments: (argument_list
    (interpreted_string_literal) @_handle_method
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def
