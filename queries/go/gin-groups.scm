;; Gin RouterGroup variable assignment pattern for Go
;; Source: tree-sitter-go grammar field names (verified against grammar.js)
;; Captures group variable name, parent router variable, and path prefix

;; RouterGroup variable: v1 := router.Group("/v1")
;; @group_var   — the new group variable name (e.g., "v1")
;; @router_obj  — the parent router/group variable (e.g., "router", "v1")
;; @route_path  — the prefix path string (e.g., "/v1")
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
