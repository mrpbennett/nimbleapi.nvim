local M = {}

local function write_file(path, content)
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")
  local fd = assert(io.open(path, "w"))
  fd:write(content)
  fd:close()
end

local function make_spring_fixture(base)
  write_file(base .. "/pom.xml", [[
<project>
  <modelVersion>4.0.0</modelVersion>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
  </dependencies>
</project>
]])

  write_file(base .. "/src/main/java/com/example/demo/DemoApplication.java", [[
package com.example.demo;

import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class DemoApplication {
}
]])

  write_file(base .. "/src/main/java/com/example/demo/TestController.java", [[
package com.example.demo;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/test")
public class TestController {
    @GetMapping
    public String get() {
        return "ok";
    }
}
]])
end

function M.run()
  local tmp = vim.fn.tempname()
  local outside = tmp .. "/outside"
  local spring_root = tmp .. "/spring-app"
  local controller = spring_root .. "/src/main/java/com/example/demo/TestController.java"

  vim.fn.mkdir(outside, "p")
  make_spring_fixture(spring_root)

  vim.cmd("cd " .. vim.fn.fnameescape(outside))

  require("nimbleapi").setup()
  require("nimbleapi.cache").invalidate_all()

  vim.cmd("edit " .. vim.fn.fnameescape(controller))

  local provider = require("nimbleapi.providers").get_provider()
  assert(provider, "expected provider to be detected from opened buffer")
  assert(provider.name == "spring", "expected spring provider, got " .. tostring(provider and provider.name))

  local routes = require("nimbleapi").get_routes()
  assert(#routes > 0, "expected routes to be extracted from detected spring project")
end

return M
