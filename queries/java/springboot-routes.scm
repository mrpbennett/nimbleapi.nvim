;; Spring Boot method-level route annotations
;; Matches: @GetMapping("/path"), @PostMapping(value="/path"), @RequestMapping(path="/path"), etc.

;; Pattern 1: Shortcut annotation with positional string argument
;; e.g., @GetMapping("/users")
(method_declaration
  (modifiers
    (annotation
      name: (identifier) @http_method
      arguments: (annotation_argument_list
        (string_literal) @route_path)))
  name: (identifier) @func_name) @route_def

;; Pattern 2: Shortcut annotation with value= or path= keyword argument
;; e.g., @GetMapping(value = "/users"), @PostMapping(path = "/users")
(method_declaration
  (modifiers
    (annotation
      name: (identifier) @http_method
      arguments: (annotation_argument_list
        (element_value_pair
          key: (identifier) @_path_key
          value: (string_literal) @route_path)
        (#any-of? @_path_key "value" "path"))))
  name: (identifier) @func_name) @route_def

;; Pattern 3: Marker annotation with no arguments (path defaults to "")
;; e.g., @GetMapping
(method_declaration
  (modifiers
    (marker_annotation
      name: (identifier) @http_method))
  name: (identifier) @func_name) @route_def

;; Pattern 4: @RequestMapping with method= only (no value=/path=)
;; e.g., @RequestMapping(method = RequestMethod.GET)
;; Path is extracted from Patterns 1/2 or defaults to "".
;; This pattern captures the method= so Lua can resolve the HTTP verb.
(method_declaration
  (modifiers
    (annotation
      name: (identifier) @http_method
      arguments: (annotation_argument_list
        (element_value_pair
          key: (identifier) @_method_key
          value: (field_access
            field: (identifier) @_request_method))
        (#eq? @_method_key "method")
        (#eq? @http_method "RequestMapping"))))
  name: (identifier) @func_name) @route_def
