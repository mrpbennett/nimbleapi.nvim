;; Route decorator on a function definition
;; Matches: @app.get("/path"), @router.post("/path"), etc.
;; Also handles keyword-only path: @app.get(path="/path")

;; Pattern 1: positional path argument (handles empty string "" too)
(decorated_definition
  (decorator
    (call
      function: (attribute
        object: (identifier) @router_obj
        attribute: (identifier) @http_method)
      arguments: (argument_list
        (string) @route_path)))
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
          value: (string) @route_path)
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

;; Pattern 4: chained attribute object with positional path — @v1.router.get("/path")
(decorated_definition
  (decorator
    (call
      function: (attribute
        object: (attribute) @router_obj
        attribute: (identifier) @http_method)
      arguments: (argument_list
        (string) @route_path)))
  definition: (function_definition
    name: (identifier) @func_name)) @route_def

;; Pattern 5: chained attribute object with keyword path — @v1.router.get(path="/path")
(decorated_definition
  (decorator
    (call
      function: (attribute
        object: (attribute) @router_obj
        attribute: (identifier) @http_method)
      arguments: (argument_list
        (keyword_argument
          name: (identifier) @_path_key
          value: (string) @route_path)
        (#eq? @_path_key "path"))))
  definition: (function_definition
    name: (identifier) @func_name)) @route_def

;; Pattern 6: chained attribute object, no-argument — @v1.router.get
(decorated_definition
  (decorator
    (attribute
      object: (attribute) @router_obj
      attribute: (identifier) @http_method))
  definition: (function_definition
    name: (identifier) @func_name)) @route_def
