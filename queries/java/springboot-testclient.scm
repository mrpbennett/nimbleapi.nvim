;; Spring Boot test client call patterns

;; Pattern 1: MockMvc — mockMvc.perform(get("/path"))
;; Matches: mockMvc.perform(get("/users")), this.mockMvc.perform(post("/users"))
(method_invocation
  object: (identifier) @client_var
  name: (identifier) @_perform
  arguments: (argument_list
    (method_invocation
      name: (identifier) @http_method
      arguments: (argument_list
        (string_literal) @test_path)))
  (#eq? @_perform "perform")) @test_call

;; Pattern 2: MockMvc static import style — perform(get("/path"))
(method_invocation
  name: (identifier) @_perform
  arguments: (argument_list
    (method_invocation
      name: (identifier) @http_method
      arguments: (argument_list
        (string_literal) @test_path)))
  (#eq? @_perform "perform")) @test_call

;; Pattern 3: WebTestClient — webTestClient.get().uri("/path")
(method_invocation
  object: (method_invocation
    object: (method_invocation
      object: (identifier) @client_var
      name: (identifier) @http_method)
    name: (identifier) @_uri
    (#eq? @_uri "uri"))
  arguments: (argument_list
    (string_literal) @test_path)) @test_call
