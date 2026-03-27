; http.NewRequest("METHOD", "/path", ...) calls in test files
(call_expression
  function: (selector_expression
    operand: (identifier) @_pkg
    field: (field_identifier) @_func
    (#eq? @_pkg "http")
    (#eq? @_func "NewRequest"))
  arguments: (argument_list
    (interpreted_string_literal) @http_method
    (interpreted_string_literal) @test_path
    .)) @test_call
