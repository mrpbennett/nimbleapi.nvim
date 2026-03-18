;; Spring Boot application entry point detection
;; Matches: @SpringBootApplication public class MyApplication { ... }

(class_declaration
  (modifiers
    (marker_annotation
      name: (identifier) @_annotation_name)
    (#eq? @_annotation_name "SpringBootApplication"))
  name: (identifier) @app_class) @app_def
