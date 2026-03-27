; httptest.NewRequest(method, "/path", ...) calls in Echo test files
; method can be a string literal ("GET") or http.MethodXxx constant (selector_expression)
(call_expression
  function: (selector_expression
    operand: (identifier) @_pkg
    field: (field_identifier) @_func
    (#eq? @_pkg "httptest")
    (#eq? @_func "NewRequest"))
  arguments: (argument_list
    (_) @http_method_expr
    (interpreted_string_literal) @test_path
    .)) @test_call
