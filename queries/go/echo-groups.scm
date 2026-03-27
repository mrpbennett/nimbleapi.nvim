;; Echo Group variable assignment pattern for Go
;; Source: tree-sitter-go grammar field names (verified against grammar.js)
;; Captures group variable name, parent echo variable, and path prefix

;; Group variable: api := e.Group("/api") or api := e.Group("/api", middleware)
;; @group_var   — the new group variable name (e.g., "api", "v1")
;; @router_obj  — the parent Echo/Group variable (e.g., "e", "api")
;; @route_path  — the prefix path string (e.g., "/api")
(short_var_declaration
  left: (expression_list
    (identifier) @group_var)
  right: (expression_list
    (call_expression
      function: (selector_expression
        operand: (identifier) @router_obj
        field: (field_identifier) @_group_method
        (#eq? @_group_method "Group"))
      arguments: (argument_list
        (interpreted_string_literal) @route_path)))) @route_def
