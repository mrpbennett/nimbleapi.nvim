;; Absolute import: from X.Y import Z
(import_from_statement
  module_name: (dotted_name) @module
  name: (dotted_name) @imported_name) @abs_import

;; Relative import: from .X.Y import Z
(import_from_statement
  module_name: (relative_import
    (import_prefix) @prefix
    (dotted_name)? @rel_module)
  name: (dotted_name) @rel_imported_name) @rel_import

;; Aliased absolute: from X import Y as Z
(import_from_statement
  module_name: (dotted_name) @alias_module
  name: (aliased_import
    name: (dotted_name) @alias_original
    alias: (identifier) @alias_name)) @alias_import

;; Aliased relative: from .X import Y as Z
(import_from_statement
  module_name: (relative_import
    (import_prefix) @rel_alias_prefix
    (dotted_name)? @rel_alias_module)
  name: (aliased_import
    name: (dotted_name) @rel_alias_original
    alias: (identifier) @rel_alias_name)) @rel_alias_import

;; Plain import: import X.Y.Z
(import_statement
  name: (dotted_name) @plain_import) @plain_import_stmt
