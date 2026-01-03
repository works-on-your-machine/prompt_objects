# frozen_string_literal: true

require "openai"
require "front_matter_parser"
require "json"

# PromptObjects: A framework where markdown files with LLM-backed behavior
# act as first-class autonomous entities.
module PromptObjects
  class Error < StandardError; end

  # Universal capabilities available to all prompt objects
  UNIVERSAL_CAPABILITIES = %i[ask_human think].freeze
end

require_relative "prompt_objects/capability"
require_relative "prompt_objects/loader"
require_relative "prompt_objects/llm/response"
require_relative "prompt_objects/llm/openai_adapter"
require_relative "prompt_objects/prompt_object"
require_relative "prompt_objects/environment"
