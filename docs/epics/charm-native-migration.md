# Charm-Native Migration

## Overview

Migrate from Marco Roth's FFI-based Charm Ruby gems (bubbletea, lipgloss, bubbles, glamour) to esmarkowski's charm-native gem, which uses native CGO extensions for better stability.

## Motivation

- **FFI Stability Issues**: Current gems have intermittent FFI-related crashes
- **Native Performance**: CGO extensions are more reliable than FFI bridges
- **Unified Library**: Single gem instead of multiple separate gems
- **Active Development**: charm-native is actively maintained

## Current Dependencies

```ruby
# Current (FFI-based)
spec.add_dependency "bubbletea"   # TUI framework
spec.add_dependency "lipgloss"    # Terminal styling
spec.add_dependency "bubbles"     # Pre-built components
spec.add_dependency "glamour"     # Markdown rendering
gem "huh", github: "marcoroth/huh-ruby"  # Interactive forms
```

## Target Dependency

```ruby
# New (CGO-based)
spec.add_dependency "charm-native"  # All-in-one native extension
```

**Repository**: https://github.com/esmarkowski/charm-native
**Local Clone**: /Users/swerner/Development/os/charm-ruby/charm-native

## API Comparison

### Lipgloss Styling

```ruby
# Current (lipgloss gem)
style = Lipgloss.new_style
  .foreground(Lipgloss.color("#FF0000"))
  .bold(true)
  .padding(1, 2)
style.render("Hello")

# charm-native (expected similar API)
# Need to verify exact API from Go bindings
```

### Bubbletea Program

```ruby
# Current (bubbletea gem)
class App
  include Bubbletea::Model

  def init
    [self, nil]
  end

  def update(msg)
    # handle messages
    [self, nil]
  end

  def view
    "Hello World"
  end
end

Bubbletea.run(App.new, alt_screen: true)

# charm-native (expected similar structure)
# Need to verify exact API
```

### Glamour Markdown

```ruby
# Current (glamour gem)
Glamour.render("# Hello\n\nWorld")

# charm-native
Charm::Native.glamour_render("# Hello\n\nWorld")  # Verify API
```

---

## charm-native Go Bindings

Based on the Go source files, charm-native exposes:

| Go File | Functionality |
|---------|---------------|
| `bubbletea.go` | Program management, terminal control |
| `lipgloss.go` | Style creation and rendering |
| `glamour.go` | Markdown rendering |
| `input.go` | Input handling |
| `keys.go` | Key message parsing |
| `terminal.go` | Terminal state management |
| `table.go` | Table rendering |
| `list.go` | List rendering |
| `tree.go` | Tree rendering |

### Exported Functions (from Go)

```go
// bubbletea.go
tea_new_program()
tea_free_program(id)
tea_upstream_version()

// lipgloss.go
lipgloss_new_style()
lipgloss_free(pointer)
lipgloss_upstream_version()
// ... style methods

// glamour.go
glamour_render(content, style)
```

---

## Migration Steps

### Step 1: Audit Current Usage

Map all current Charm gem usage in our codebase:

**Files to audit:**
- `lib/prompt_objects/ui/app.rb`
- `lib/prompt_objects/ui/styles.rb`
- `lib/prompt_objects/ui/models/*.rb`

**Usage patterns:**
- [ ] Bubbletea::Model inclusion
- [ ] Bubbletea.run()
- [ ] Bubbletea.quit
- [ ] Bubbletea.send_message()
- [ ] KeyMessage handling
- [ ] WindowSizeMessage handling
- [ ] Lipgloss style creation
- [ ] Lipgloss.render()
- [ ] Glamour rendering (if used)

### Step 2: Create Compatibility Layer

If APIs differ significantly, create a thin wrapper:

```ruby
# lib/prompt_objects/ui/charm_compat.rb
module PromptObjects
  module UI
    module CharmCompat
      # Wrap charm-native to match our current API expectations
      module Bubbletea
        def self.run(model, alt_screen: false)
          # Translate to charm-native API
        end

        def self.quit
          # Translate
        end
      end

      module Lipgloss
        def self.new_style
          # Translate
        end
      end
    end
  end
end
```

### Step 3: Update Dependencies

```ruby
# Gemfile
# Remove FFI gems
# gem "bubbletea"
# gem "lipgloss"
# gem "bubbles"
# gem "glamour"
# gem "huh"

# Add charm-native
gem "charm-native", path: "/Users/swerner/Development/os/charm-ruby/charm-native"
# Or once published:
# gem "charm-native"
```

### Step 4: Update Requires

```ruby
# Before
require "bubbletea"
require "lipgloss"

# After
require "charm/native"
# Or with compat layer:
require_relative "charm_compat"
```

### Step 5: Update Code

Systematically update each file:

1. **styles.rb**: Update Lipgloss usage
2. **app.rb**: Update Bubbletea usage
3. **models/*.rb**: Update any direct Charm usage

### Step 6: Test Thoroughly

- [ ] App launches without crashes
- [ ] All key bindings work
- [ ] Styling renders correctly
- [ ] Window resize works
- [ ] No memory leaks
- [ ] No FFI errors

### Step 7: Remove Old Dependencies

Once migration is complete and tested:
- Remove old gem dependencies from gemspec
- Clean up any compatibility shims if not needed

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| API incompatibility | Medium | High | Create compat layer |
| Missing features | Low | Medium | Contribute to charm-native |
| Build issues | Medium | Medium | Test on multiple platforms |
| Performance regression | Low | Low | Benchmark before/after |

## Testing Strategy

1. **Unit Tests**: Test each component with new bindings
2. **Integration**: Full app startup and interaction
3. **Platform Testing**: macOS, Linux (if applicable)
4. **Stress Testing**: Extended usage to catch memory issues

## Rollback Plan

If migration fails:
1. Keep old gems as fallback
2. Feature flag to switch implementations
3. Can revert Gemfile changes quickly

---

## Open Questions

1. Is charm-native API stable enough for production?
2. What's the release/publishing plan for the gem?
3. Any missing features compared to current gems?
4. Can we contribute missing features upstream?

---

## Timeline Estimate

- **Step 1-2**: Audit & Compat Layer - 1-2 hours
- **Step 3-5**: Migration - 2-4 hours
- **Step 6-7**: Testing & Cleanup - 1-2 hours

Total: ~1 day of focused work

---

## References

- **charm-native**: https://github.com/esmarkowski/charm-native
- **Current bubbletea**: https://github.com/marcoroth/bubbletea-ruby
- **Current lipgloss**: https://github.com/marcoroth/lipgloss-ruby
- **Charm Go libraries**: https://github.com/charmbracelet
