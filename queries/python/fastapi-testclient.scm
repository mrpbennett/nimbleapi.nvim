;; Test client calls: client.get("/path"), client.post("/path"), etc.
(call
  function: (attribute
    object: (identifier) @client_var
    attribute: (identifier) @http_method)
  arguments: (argument_list
    .
    (string
      (string_content) @test_path))) @test_call
