# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "prompt_objects"
  spec.version       = "0.4.0"
  spec.authors       = ["Scott Werner"]
  spec.email         = ["scott@sublayer.com"]

  spec.summary       = "LLM-backed entities as first-class autonomous objects"
  spec.description   = "A framework where markdown files with LLM-backed behavior act as first-class autonomous entities. Features inter-object communication and environment management."
  spec.homepage      = "https://github.com/works-on-your-machine/prompt_objects"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Include lib, exe, templates, and objects (stdlib)
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[test/ spec/ features/ .git .github docs/])
    end
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "ruby-openai", "~> 7.0"
  spec.add_dependency "anthropic", "~> 1.0"
  spec.add_dependency "front_matter_parser", "~> 1.0"
  spec.add_dependency "sqlite3", "~> 2.0"

  # Web server dependencies
  spec.add_dependency "falcon", "~> 0.50"
  spec.add_dependency "async-websocket", "~> 0.28"
  spec.add_dependency "rack", "~> 3.0"
  spec.add_dependency "listen", "~> 3.9"

  # MCP server
  spec.add_dependency "mcp", "~> 0.4"

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "debug", "~> 1.0"
end
