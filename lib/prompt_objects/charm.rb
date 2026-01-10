# frozen_string_literal: true

# Charm Library Loader
#
# This file loads the Charm libraries (Bubbletea, Lipgloss, Glamour) using
# charm-native as the native backend, plus our Ruby shims for additional
# functionality (Model, Runner, Messages, Commands, etc.)
#
# Instead of `require "bubbletea"`, use `require_relative "charm"` to get
# the unified charm-native-backed libraries without FFI crashes.

# Load vendor path for our shims
vendor_path = File.expand_path("../../../vendor/charm_shim", __FILE__)
$LOAD_PATH.unshift(vendor_path) unless $LOAD_PATH.include?(vendor_path)

# Load charm-native first (provides native Bubbletea, Lipgloss, Glamour modules)
require "charm/native"

# Load our Ruby shims on top (adds Model, Runner, Messages, Commands, etc.)
require "bubbletea"
require "lipgloss"
require "glamour"
