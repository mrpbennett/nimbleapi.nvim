;; Spring Boot application entry point detection
;; Matches: @SpringBootApplication public class MyApplication { ... }

;; Pattern 1: bare marker annotation — @SpringBootApplication
(class_declaration
  (modifiers
    (marker_annotation
      name: (identifier) @_annotation_name)
    (#eq? @_annotation_name "SpringBootApplication"))
  name: (identifier) @app_class) @app_def

;; Pattern 2: annotation with arguments — @SpringBootApplication(scanBasePackages = "...")
(class_declaration
  (modifiers
    (annotation
      name: (identifier) @_annotation_name)
    (#eq? @_annotation_name "SpringBootApplication"))
  name: (identifier) @app_class) @app_def
