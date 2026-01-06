# Charm-Native Migration

## Overview

Track the upstream fix for FFI stability issues in Marco Roth's Charm Ruby gems. The root cause is multiple Go runtimes conflicting when separate gems are loaded. The solution (charm-native) consolidates all Go code into a single native extension.

## Status: PENDING SPENCER'S FORKS

**Plan:** Use Spencer (esmarkowski)'s forked gems that integrate charm-native. He has working demos with all gems consolidated.

**Next steps:**
1. Get Spencer's forked gem repos (asked in GitHub comments)
2. Update Gemfile to point to his forks
3. Test our TUI with the new gems
4. Switch back to Marco's official gems when he integrates charm-native

## The Problem

- **Root Cause**: Multiple Go runtimes conflict when loading bubbletea + lipgloss + glamour
- **Error**: `runtime: g 17: unexpected return pc for _cgoexp_...`
- **Discussion**: https://github.com/marcoroth/bubbletea-ruby/issues/1

## The Solution (charm-native)

esmarkowski created charm-native as a proof-of-concept:
- Consolidates all Charm Go extensions into single native library
- Gems would depend on charm-native instead of bundling their own Go code
- Ruby API stays the same - only the native layer changes

## Why Wait vs Migrate Now

| Approach | Pros | Cons |
|----------|------|------|
| **Wait for upstream** | No code changes, automatic fix | Dependent on Marco's timeline |
| **Use charm-native directly** | Fix now | Low-level API only, need to reimplement Ruby layer |
| **Fork & integrate ourselves** | Control timeline | Maintenance burden |

**Verdict**: charm-native provides low-level Go bindings, not the high-level Ruby API (Model, Runner, Commands). We'd have to reimplement all of that ourselves. Not worth it when the upstream fix is in progress.

## Workaround (Current)

The FFI issues are intermittent. Current mitigations:
- Restart app if crash occurs
- The crashes seem less frequent in recent gem versions
- Single Bubble Tea program architecture helps (we already do this)

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
