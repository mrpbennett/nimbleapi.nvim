;; include_router() calls
;; Pattern 1: app.include_router(module.router, ...)
(call
  function: (attribute
    object: (identifier) @app_var
    attribute: (identifier) @method_name
    (#eq? @method_name "include_router"))
  arguments: (argument_list
    .
    (attribute
      object: (identifier) @router_module
      attribute: (identifier) @router_attr))) @include_call

;; Pattern 2: app.include_router(router_var, ...)
(call
  function: (attribute
    object: (identifier) @app_var
    attribute: (identifier) @method_name
    (#eq? @method_name "include_router"))
  arguments: (argument_list
    .
    (identifier) @router_var)) @include_call
