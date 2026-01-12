# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in prompt_objects.gemspec
gemspec

# Ruby 3.4+ compatibility - base64 moved out of stdlib
gem "base64"

# charm-native provides unified Go runtime for Bubbletea/Lipgloss/Glamour
# This avoids the FFI crash from multiple Go runtimes
gem "charm-native", path: "../charm-native"

# huh is not on rubygems yet, specify separately
# NOTE: huh requires the original charm gems, so commenting out for now
# gem "huh", github: "marcoroth/huh-ruby"
