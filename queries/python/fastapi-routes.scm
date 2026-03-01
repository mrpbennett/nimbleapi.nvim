;; Route decorator on a function definition
;; Matches: @app.get("/path"), @router.post("/path"), etc.
;; Also handles keyword-only path: @app.get(path="/path")

;; Pattern 1: positional path argument
(decorated_definition
  (decorator
    (call
      function: (attribute
        object: (identifier) @router_obj
        attribute: (identifier) @http_method)
      arguments: (argument_list
        (string
          (string_content) @route_path))))
  definition: (function_definition
    name: (identifier) @func_name)) @route_def

;; Pattern 2: keyword path argument — @app.get(path="/path")
(decorated_definition
  (decorator
    (call
      function: (attribute
        object: (identifier) @router_obj
        attribute: (identifier) @http_method)
      arguments: (argument_list
        (keyword_argument
          name: (identifier) @_path_key
          value: (string
            (string_content) @route_path))
        (#eq? @_path_key "path"))))
  definition: (function_definition
    name: (identifier) @func_name)) @route_def

;; Pattern 3: no-argument decorator — @app.get (uncommon, path defaults to "/")
(decorated_definition
  (decorator
    (attribute
      object: (identifier) @router_obj
      attribute: (identifier) @http_method))
  definition: (function_definition
    name: (identifier) @func_name)) @route_def
