;; Direct route calls: app.METHOD('/path', handler)
;; Also matches router.METHOD('/path', handler) — router_obj captures the variable name
;; Excludes app.use() via #match? predicate — only HTTP verbs and "all" pass through
;; Source: verified against JavaScript/TypeScript tree-sitter grammar (2026-03-27)

(call_expression
  function: (member_expression
    object: (identifier) @router_obj
    property: (property_identifier) @http_method
    (#match? @http_method "^(get|post|put|delete|patch|options|head|all)$"))
  arguments: (arguments
    (string
      (string_fragment) @route_path)
    .
    (_) @func_name)) @route_def
