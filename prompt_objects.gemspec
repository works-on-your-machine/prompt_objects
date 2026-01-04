# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "prompt_objects"
  spec.version       = "0.1.0"
  spec.authors       = ["Your Name"]
  spec.email         = ["your@email.com"]

  spec.summary       = "LLM-backed entities as first-class autonomous objects"
  spec.description   = "A framework where markdown files with LLM-backed behavior act as first-class autonomous entities. Features a TUI interface, inter-object communication, and environment management."
  spec.homepage      = "https://github.com/yourusername/prompt_objects"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

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
  spec.add_dependency "front_matter_parser"

  # TUI dependencies (Charm Ruby ports)
  spec.add_dependency "bubbletea"
  spec.add_dependency "lipgloss"
  spec.add_dependency "bubbles"
  spec.add_dependency "glamour"

  # MCP server
  spec.add_dependency "mcp"

  # Development dependencies
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "debug"
end
