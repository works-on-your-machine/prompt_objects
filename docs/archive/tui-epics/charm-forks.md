> **ARCHIVED**: This epic was for the Charm-based TUI interface. The project has pivoted to a web-based interface (see docs/web-server-design.md and docs/epics/web-*.md). This file is preserved for historical reference.

---

# Charm Gem Forks: Using charm-native

## Status: Done ✓

Completed January 2026. charm-native is integrated with Ruby shims in `vendor/charm_shim/`.

## Overview

~~Fork Marco's Charm Ruby gems to~~ Use the consolidated `charm-native` extension instead of each gem building its own Go extension. This fixes the FFI crash caused by multiple Go runtimes in one process.

**Solution implemented:**
- Built charm-native from esmarkowski/charm-native (Go archive + C extension)
- Created Ruby shims for Bubbletea (Model, Runner, Messages, Commands), Lipgloss (Position, Border, Color), and Glamour (Style, StyleDefinition)
- All Charm functionality works with single Go runtime - no more crashes

## The Problem

```
Current: Each gem has its own Go extension
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  bubbletea-ruby  │  │  lipgloss-ruby   │  │   glamour-ruby   │
│  ┌────────────┐  │  │  ┌────────────┐  │  │  ┌────────────┐  │
│  │ Go Runtime │  │  │  │ Go Runtime │  │  │  │ Go Runtime │  │
│  └────────────┘  │  │  └────────────┘  │  │  └────────────┘  │
└──────────────────┘  └──────────────────┘  └──────────────────┘
        ↓                     ↓                     ↓
              CONFLICT! Multiple Go runtimes crash
```

## The Solution

```
Proposed: All gems share charm-native
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  bubbletea-ruby  │  │  lipgloss-ruby   │  │   glamour-ruby   │
│    (pure Ruby    │  │    (pure Ruby    │  │    (pure Ruby    │
│     + FFI)       │  │     + FFI)       │  │     + FFI)       │
└────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
         │                     │                     │
         └─────────────────────┼─────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    │    charm-native     │
                    │  ┌────────────────┐ │
                    │  │ Single Go      │ │
                    │  │ Runtime        │ │
                    │  └────────────────┘ │
                    └─────────────────────┘
```

## What charm-native Already Provides

All the Go functions are already exported and ready:

**Bubbletea functions:**
- `tea_new_program`, `tea_free_program`, `tea_free`
- `tea_terminal_init`, `tea_terminal_enter_raw_mode`, `tea_terminal_exit_raw_mode`
- `tea_terminal_enter_alt_screen`, `tea_terminal_exit_alt_screen`
- `tea_terminal_hide_cursor`, `tea_terminal_show_cursor`
- `tea_terminal_enable_mouse_cell_motion`, `tea_terminal_enable_mouse_all_motion`, `tea_terminal_disable_mouse`
- `tea_terminal_enable_bracketed_paste`, `tea_terminal_disable_bracketed_paste`
- `tea_terminal_enable_report_focus`, `tea_terminal_disable_report_focus`
- `tea_terminal_get_size`, `tea_terminal_set_window_title`
- `tea_input_start_reader`, `tea_input_stop_reader`, `tea_input_read_raw`
- `tea_parse_input_with_consumed`, `tea_get_key_name`
- `tea_renderer_new`, `tea_renderer_render`, `tea_renderer_set_size`, `tea_renderer_set_alt_screen`, `tea_renderer_clear`
- `tea_string_width`

**Glamour functions:**
- `glamour_render`, `glamour_render_with_width`, `glamour_render_with_options`
- `glamour_render_with_json_style`
- `glamour_free`

**Lipgloss functions:**
- `lipgloss_new_style`, `lipgloss_free`
- Style methods (foreground, background, padding, margin, bold, etc.)
- `lipgloss_render`

---

## Fork Strategy

### Option A: Minimal Fork (Recommended)

Fork each gem and replace the C extension with Ruby FFI calls to charm-native.

**Pros:**
- Ruby API stays identical (drop-in replacement)
- Existing code (Model, Runner, Commands) unchanged
- Easy to maintain - just the native bridge changes

**Cons:**
- Need to maintain 3+ forks
- Must track upstream changes

### Option B: Create New Unified Gem

Create a single `charm-ruby` gem that provides all APIs.

**Pros:**
- Single gem to maintain
- Cleaner namespace

**Cons:**
- Breaking API change
- More migration work for users

**Verdict:** Option A - minimal forks are lower risk and faster to implement.

---

## Implementation: bubbletea-ruby Fork

### Step 1: Fork and Clone

```bash
# Fork on GitHub, then:
git clone git@github.com:YOUR_USER/bubbletea-ruby.git
cd bubbletea-ruby
git remote add upstream https://github.com/marcoroth/bubbletea-ruby.git
```

### Step 2: Remove Native Extension

```bash
rm -rf ext/
rm -rf go/
```

### Step 3: Update Gemspec

```ruby
# bubbletea.gemspec
Gem::Specification.new do |spec|
  spec.name = "bubbletea"
  # ... existing metadata ...

  # Remove native extension
  # spec.extensions = ["ext/bubbletea/extconf.rb"]  # DELETE THIS

  # Add charm-native dependency
  spec.add_dependency "charm-native", "~> 0.1"
  spec.add_dependency "ffi", "~> 1.15"

  # Update files list - no ext/ or go/
  spec.files = Dir["lib/**/*.rb", "LICENSE.txt", "README.md"]
end
```

### Step 4: Create FFI Bridge

```ruby
# lib/bubbletea/native.rb
require "ffi"
require "charm/native"

module Bubbletea
  module Native
    extend FFI::Library

    # Load charm-native shared library
    ffi_lib Charm::Native.library_path

    # Program management
    attach_function :tea_new_program, [], :uint64
    attach_function :tea_free_program, [:uint64], :void
    attach_function :tea_free, [:pointer], :void

    # Terminal control
    attach_function :tea_terminal_init, [:uint64], :int
    attach_function :tea_terminal_enter_raw_mode, [:uint64], :int
    attach_function :tea_terminal_exit_raw_mode, [:uint64], :int
    attach_function :tea_terminal_enter_alt_screen, [:uint64], :void
    attach_function :tea_terminal_exit_alt_screen, [:uint64], :void
    attach_function :tea_terminal_hide_cursor, [:uint64], :void
    attach_function :tea_terminal_show_cursor, [:uint64], :void
    attach_function :tea_terminal_get_size, [:uint64, :pointer, :pointer], :int
    attach_function :tea_terminal_set_window_title, [:string], :void
    attach_function :tea_terminal_is_tty, [], :int

    # Mouse
    attach_function :tea_terminal_enable_mouse_cell_motion, [:uint64], :void
    attach_function :tea_terminal_enable_mouse_all_motion, [:uint64], :void
    attach_function :tea_terminal_disable_mouse, [:uint64], :void

    # Bracketed paste & focus
    attach_function :tea_terminal_enable_bracketed_paste, [:uint64], :void
    attach_function :tea_terminal_disable_bracketed_paste, [:uint64], :void
    attach_function :tea_terminal_enable_report_focus, [:uint64], :void
    attach_function :tea_terminal_disable_report_focus, [:uint64], :void

    # Input
    attach_function :tea_input_start_reader, [:uint64], :int
    attach_function :tea_input_stop_reader, [:uint64], :void
    attach_function :tea_input_read_raw, [:uint64, :pointer, :int, :int], :int

    # Input parsing
    attach_function :tea_parse_input_with_consumed, [:pointer, :int, :pointer], :pointer
    attach_function :tea_get_key_name, [:int], :pointer

    # Renderer
    attach_function :tea_renderer_new, [:uint64], :uint64
    attach_function :tea_renderer_render, [:uint64, :string], :void
    attach_function :tea_renderer_set_size, [:uint64, :int, :int], :void
    attach_function :tea_renderer_set_alt_screen, [:uint64, :int], :void
    attach_function :tea_renderer_clear, [:uint64], :void

    # String utilities
    attach_function :tea_string_width, [:string], :int
  end
end
```

### Step 5: Create Program Class (Ruby)

```ruby
# lib/bubbletea/program.rb
module Bubbletea
  class Program
    def initialize
      @handle = Native.tea_new_program
      Native.tea_terminal_init(@handle)
    end

    def enter_raw_mode
      Native.tea_terminal_enter_raw_mode(@handle) == 0
    end

    def exit_raw_mode
      Native.tea_terminal_exit_raw_mode(@handle) == 0
    end

    def enter_alt_screen
      Native.tea_terminal_enter_alt_screen(@handle)
    end

    def exit_alt_screen
      Native.tea_terminal_exit_alt_screen(@handle)
    end

    def hide_cursor
      Native.tea_terminal_hide_cursor(@handle)
    end

    def show_cursor
      Native.tea_terminal_show_cursor(@handle)
    end

    def enable_mouse_cell_motion
      Native.tea_terminal_enable_mouse_cell_motion(@handle)
    end

    def enable_mouse_all_motion
      Native.tea_terminal_enable_mouse_all_motion(@handle)
    end

    def disable_mouse
      Native.tea_terminal_disable_mouse(@handle)
    end

    def enable_bracketed_paste
      Native.tea_terminal_enable_bracketed_paste(@handle)
    end

    def disable_bracketed_paste
      Native.tea_terminal_disable_bracketed_paste(@handle)
    end

    def enable_report_focus
      Native.tea_terminal_enable_report_focus(@handle)
    end

    def disable_report_focus
      Native.tea_terminal_disable_report_focus(@handle)
    end

    def terminal_size
      width_ptr = FFI::MemoryPointer.new(:int)
      height_ptr = FFI::MemoryPointer.new(:int)

      if Native.tea_terminal_get_size(@handle, width_ptr, height_ptr) == 0
        [width_ptr.read_int, height_ptr.read_int]
      else
        nil
      end
    end

    def start_input_reader
      Native.tea_input_start_reader(@handle) == 0
    end

    def stop_input_reader
      Native.tea_input_stop_reader(@handle)
    end

    def poll_event(timeout_ms)
      buffer = FFI::MemoryPointer.new(:char, 256)
      bytes_read = Native.tea_input_read_raw(@handle, buffer, 256, timeout_ms)

      return nil if bytes_read <= 0

      consumed_ptr = FFI::MemoryPointer.new(:int)
      json_ptr = Native.tea_parse_input_with_consumed(buffer, bytes_read, consumed_ptr)

      return nil if json_ptr.null?

      json_str = json_ptr.read_string
      Native.tea_free(json_ptr)

      return nil if json_str.empty?

      JSON.parse(json_str)
    end

    def create_renderer
      Native.tea_renderer_new(@handle)
    end

    def render(renderer_id, view)
      Native.tea_renderer_render(renderer_id, view)
    end

    def renderer_set_size(renderer_id, width, height)
      Native.tea_renderer_set_size(renderer_id, width, height)
    end

    def renderer_set_alt_screen(renderer_id, enabled)
      Native.tea_renderer_set_alt_screen(renderer_id, enabled ? 1 : 0)
    end

    def renderer_clear(renderer_id)
      Native.tea_renderer_clear(renderer_id)
    end

    def string_width(str)
      Native.tea_string_width(str)
    end

    private

    def finalize
      Native.tea_free_program(@handle) if @handle
    end
  end
end
```

### Step 6: Update Main Loader

```ruby
# lib/bubbletea.rb
require_relative "bubbletea/version"
require_relative "bubbletea/native"
require_relative "bubbletea/program"
require_relative "bubbletea/messages"
require_relative "bubbletea/commands"
require_relative "bubbletea/model"
require_relative "bubbletea/runner"

module Bubbletea
  class Error < StandardError; end

  def self.tty?
    Native.tea_terminal_is_tty == 1
  end

  def self._set_window_title(title)
    Native.tea_terminal_set_window_title(title)
  end

  def self.get_key_name(key_type)
    ptr = Native.tea_get_key_name(key_type)
    return "" if ptr.null?
    name = ptr.read_string
    # Note: Don't free this - it's a static string in Go
    name
  end
end
```

### Step 7: Test

```bash
bundle install
bundle exec ruby -e "require 'bubbletea'; puts Bubbletea.tty?"
```

---

## Implementation: glamour-ruby Fork

Glamour is simpler - just markdown rendering.

### FFI Bridge

```ruby
# lib/glamour/native.rb
require "ffi"
require "charm/native"

module Glamour
  module Native
    extend FFI::Library
    ffi_lib Charm::Native.library_path

    attach_function :glamour_render, [:string, :string], :pointer
    attach_function :glamour_render_with_width, [:string, :string, :int], :pointer
    attach_function :glamour_render_with_options, [
      :string,  # markdown
      :string,  # style
      :int,     # width
      :int,     # emoji
      :int,     # preserve_newlines
      :string,  # base_url
      :int      # color_profile
    ], :pointer
    attach_function :glamour_free, [:pointer], :void
  end
end
```

### Main API

```ruby
# lib/glamour.rb
require_relative "glamour/native"

module Glamour
  def self.render(markdown, style: "auto", width: 0)
    ptr = if width > 0
            Native.glamour_render_with_width(markdown, style, width)
          else
            Native.glamour_render(markdown, style)
          end

    return "" if ptr.null?

    result = ptr.read_string
    Native.glamour_free(ptr)
    result
  end
end
```

---

## Implementation: lipgloss-ruby Fork

Lipgloss is more complex with style objects.

### FFI Bridge

```ruby
# lib/lipgloss/native.rb
require "ffi"
require "charm/native"

module Lipgloss
  module Native
    extend FFI::Library
    ffi_lib Charm::Native.library_path

    # Style management
    attach_function :lipgloss_new_style, [], :uint64
    attach_function :lipgloss_copy_style, [:uint64], :uint64
    attach_function :lipgloss_free_style, [:uint64], :void

    # Style setters (return new style ID)
    attach_function :lipgloss_foreground, [:uint64, :string], :uint64
    attach_function :lipgloss_background, [:uint64, :string], :uint64
    attach_function :lipgloss_bold, [:uint64, :int], :uint64
    attach_function :lipgloss_italic, [:uint64, :int], :uint64
    attach_function :lipgloss_underline, [:uint64, :int], :uint64
    attach_function :lipgloss_padding, [:uint64, :int, :int, :int, :int], :uint64
    attach_function :lipgloss_margin, [:uint64, :int, :int, :int, :int], :uint64
    attach_function :lipgloss_width, [:uint64, :int], :uint64
    attach_function :lipgloss_height, [:uint64, :int], :uint64
    attach_function :lipgloss_align, [:uint64, :int], :uint64

    # Rendering
    attach_function :lipgloss_render, [:uint64, :string], :pointer
    attach_function :lipgloss_free, [:pointer], :void
  end
end
```

### Style Class

```ruby
# lib/lipgloss/style.rb
module Lipgloss
  class Style
    def initialize(handle = nil)
      @handle = handle || Native.lipgloss_new_style
    end

    def foreground(color)
      Style.new(Native.lipgloss_foreground(@handle, color.to_s))
    end

    def background(color)
      Style.new(Native.lipgloss_background(@handle, color.to_s))
    end

    def bold(enabled = true)
      Style.new(Native.lipgloss_bold(@handle, enabled ? 1 : 0))
    end

    def italic(enabled = true)
      Style.new(Native.lipgloss_italic(@handle, enabled ? 1 : 0))
    end

    def underline(enabled = true)
      Style.new(Native.lipgloss_underline(@handle, enabled ? 1 : 0))
    end

    def padding(top, right = top, bottom = top, left = right)
      Style.new(Native.lipgloss_padding(@handle, top, right, bottom, left))
    end

    def margin(top, right = top, bottom = top, left = right)
      Style.new(Native.lipgloss_margin(@handle, top, right, bottom, left))
    end

    def width(w)
      Style.new(Native.lipgloss_width(@handle, w))
    end

    def height(h)
      Style.new(Native.lipgloss_height(@handle, h))
    end

    def render(text)
      ptr = Native.lipgloss_render(@handle, text)
      return "" if ptr.null?
      result = ptr.read_string
      Native.lipgloss_free(ptr)
      result
    end

    # Finalizer to free Go memory
    def self.release(handle)
      proc { Native.lipgloss_free_style(handle) }
    end
  end

  def self.new_style
    Style.new
  end
end
```

---

## charm-native Dependency

The charm-native gem needs to be published or referenced by path/git.

```ruby
# Gemfile for prompt_objects
gem "charm-native", path: "../charm-native"
# Or when published:
# gem "charm-native", "~> 0.1"

gem "bubbletea", git: "https://github.com/YOUR_USER/bubbletea-ruby", branch: "charm-native"
gem "lipgloss", git: "https://github.com/YOUR_USER/lipgloss-ruby", branch: "charm-native"
gem "glamour", git: "https://github.com/YOUR_USER/glamour-ruby", branch: "charm-native"
```

---

## Effort Estimate

| Task | Estimate |
|------|----------|
| Fork bubbletea-ruby, create FFI bridge | 4-6 hours |
| Fork lipgloss-ruby, create FFI bridge | 2-3 hours |
| Fork glamour-ruby, create FFI bridge | 1-2 hours |
| Update prompt_objects to use forks | 1-2 hours |
| Testing and debugging | 4-6 hours |
| **Total** | **~2-3 days** |

---

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| FFI signature mismatch | Medium | Test each function individually |
| Memory leaks | Medium | Careful use of `free` functions |
| charm-native missing functions | Low | Already verified all functions exist |
| API differences in Ruby layer | Low | Keep Ruby layer unchanged |

---

## Testing Strategy

1. **Unit tests for FFI bridge** - Call each native function
2. **Integration test** - Run existing bubbletea demo
3. **prompt_objects test** - Run our TUI with forked gems
4. **Multi-gem test** - Verify no crash with all gems loaded

---

## Success Criteria

- [ ] All three forked gems install without errors
- [ ] Simple Bubbletea app runs without crash
- [ ] Lipgloss styling works correctly
- [ ] Glamour markdown renders properly
- [ ] prompt_objects TUI runs stably
- [ ] No "multiple Go runtime" crashes

---

## Repository Structure

```
github.com/YOUR_ORG/
├── charm-native/          # Fork of esmarkowski/charm-native
├── bubbletea-ruby/        # Fork with charm-native branch
├── lipgloss-ruby/         # Fork with charm-native branch
└── glamour-ruby/          # Fork with charm-native branch
```

---

## Long-term Maintenance

- **Track upstream** - Periodically merge from Marco's repos
- **Contribute back** - If this works, propose upstream integration
- **Single source of truth** - charm-native is the only place Go code lives
