;; FastAPI() instantiation
;; Matches: app = FastAPI(), app = FastAPI(title="My API"), etc.
(assignment
  left: (identifier) @app_var
  right: (call
    function: (identifier) @call_name
    (#eq? @call_name "FastAPI"))) @app_assignment
