;; Spring Boot class-level @RequestMapping prefix extraction
;; Matches: @RequestMapping("/api/v1"), @RestController + @RequestMapping(value="/api")

;; Pattern 1: @RequestMapping with positional string argument on a class
(class_declaration
  (modifiers
    (annotation
      name: (identifier) @_annotation_name
      arguments: (annotation_argument_list
        (string_literal) @class_prefix))
    (#eq? @_annotation_name "RequestMapping"))
  name: (identifier) @class_name) @controller_def

;; Pattern 2: @RequestMapping with value= or path= keyword argument on a class
(class_declaration
  (modifiers
    (annotation
      name: (identifier) @_annotation_name
      arguments: (annotation_argument_list
        (element_value_pair
          key: (identifier) @_path_key
          value: (string_literal) @class_prefix))
      (#eq? @_annotation_name "RequestMapping")
      (#any-of? @_path_key "value" "path")))
  name: (identifier) @class_name) @controller_def

;; Pattern 3: @RestController or @Controller without @RequestMapping (no prefix)
(class_declaration
  (modifiers
    (marker_annotation
      name: (identifier) @_annotation_name)
    (#any-of? @_annotation_name "RestController" "Controller"))
  name: (identifier) @class_name) @controller_def
