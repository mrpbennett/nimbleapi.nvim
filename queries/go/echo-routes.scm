;; Echo route registration patterns for Go
;; Source: tree-sitter-go grammar field names (verified against grammar.js)
;; Capture names follow nimbleapi.nvim convention:
;;   @router_obj, @http_method, @route_path, @func_name, @route_def

;; Pattern 1: Method shortcuts — e.GET("/path", handler), e.POST(...), e.Any(...), etc.
;; Also matches e.CONNECT, e.TRACE, e.Any — Lua side filters by ECHO_METHODS table
(call_expression
  function: (selector_expression
    operand: (identifier) @router_obj
    field: (field_identifier) @http_method)
  arguments: (argument_list
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def

;; Pattern 2: Add — e.Add("GET", "/path", handler)
;; @_add_method captures the first string arg (the HTTP method)
;; @http_method captures "Add" — Lua side checks this to switch to @_add_method
(call_expression
  function: (selector_expression
    operand: (identifier) @router_obj
    field: (field_identifier) @http_method
    (#eq? @http_method "Add"))
  arguments: (argument_list
    (interpreted_string_literal) @_add_method
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def
