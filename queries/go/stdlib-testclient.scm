;; stdlib test client pattern for Go — httptest.NewRequest
;; Source: tree-sitter-go grammar field names (verified from grammar.js)
;; Matches: httptest.NewRequest("METHOD", "/path", ...) calls in *_test.go files
;; Capture names follow nimbleapi.nvim test client convention:
;;   @_pkg and @_func are internal (prefixed _), filtered by #eq? predicates
;;   @http_method = first string arg ("GET", "POST", etc.)
;;   @test_path   = second string arg ("/users/123")
;;   @test_call   = full call expression node (for line number)

(call_expression
  function: (selector_expression
    operand: (identifier) @_pkg
    field: (field_identifier) @_func
    (#eq? @_pkg "httptest")
    (#eq? @_func "NewRequest"))
  arguments: (argument_list
    (interpreted_string_literal) @http_method
    (interpreted_string_literal) @test_path
    .)) @test_call
