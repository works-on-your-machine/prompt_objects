# frozen_string_literal: true

# Bubbletea shim for charm-native
#
# This file loads charm-native (which provides Bubbletea::Program via C extension)
# and adds the Ruby-only components (Model, Runner, Messages, Commands) on top.
#
# Based on marcoroth/bubbletea-ruby v0.1.0

# First, load charm-native which provides the native Bubbletea module
require "charm/native"

# Now add Ruby-only components to the existing Bubbletea module
require_relative "bubbletea/messages"
require_relative "bubbletea/commands"
require_relative "bubbletea/model"
require_relative "bubbletea/runner"

module Bubbletea
  VERSION = "0.1.0"

  class Error < StandardError; end
end
