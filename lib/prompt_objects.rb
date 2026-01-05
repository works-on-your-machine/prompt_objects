# frozen_string_literal: true

require "openai"
require "front_matter_parser"
require "json"

# PromptObjects: A framework where markdown files with LLM-backed behavior
# act as first-class autonomous entities.
module PromptObjects
  class Error < StandardError; end

  # Universal capabilities available to all prompt objects (don't need to be declared)
  UNIVERSAL_CAPABILITIES = %w[ask_human think create_capability add_capability list_capabilities].freeze
end

require_relative "prompt_objects/capability"
require_relative "prompt_objects/primitive"
require_relative "prompt_objects/registry"
require_relative "prompt_objects/message_bus"
require_relative "prompt_objects/human_queue"
require_relative "prompt_objects/loader"
require_relative "prompt_objects/llm/response"
require_relative "prompt_objects/llm/openai_adapter"
require_relative "prompt_objects/prompt_object"

# Environment module (must be loaded before environment.rb which uses them)
require_relative "prompt_objects/environment/manifest"
require_relative "prompt_objects/environment/manager"
require_relative "prompt_objects/environment/git"
require_relative "prompt_objects/environment"

# Session storage
require_relative "prompt_objects/session/store"

# Built-in primitives
require_relative "prompt_objects/primitives/read_file"
require_relative "prompt_objects/primitives/list_files"
require_relative "prompt_objects/primitives/write_file"
require_relative "prompt_objects/primitives/http_get"

# Universal capabilities (available to all prompt objects)
require_relative "prompt_objects/universal/ask_human"
require_relative "prompt_objects/universal/think"
require_relative "prompt_objects/universal/create_capability"
require_relative "prompt_objects/universal/add_capability"
require_relative "prompt_objects/universal/list_capabilities"
