# Web Distribution

**Status**: Backlog
**Priority**: Medium
**Depends on**: [web-ui-complete.md](web-ui-complete.md)
**Design doc**: [web-server-design.md](../web-server-design.md)

## Overview

Integrate the web server into the gem's CLI and bundle the frontend assets for distribution. After this epic, users can `gem install prompt_objects` and run `prompt_objects serve ./my-env`.

## Goals

- `prompt_objects serve` command in CLI
- Frontend assets bundled with gem
- Export/import .poenv bundles
- Clean installation and first-run experience

## Non-Goals

- Cloud hosting
- Authentication
- Auto-update mechanism

---

## Tasks

### CLI Integration

- [ ] Add `serve` command to Thor CLI
  - [ ] `prompt_objects serve PATH` - serve an environment
  - [ ] `--port` / `-p` option (default 3000)
  - [ ] `--host` / `-h` option (default localhost)
  - [ ] `--open` / `-o` flag to open browser automatically
- [ ] Support serving .poenv bundles directly
  - [ ] Extract to temp directory
  - [ ] Serve from there
  - [ ] Clean up on exit
- [ ] Graceful shutdown on Ctrl+C
- [ ] Startup banner with URL and instructions

### Frontend Bundling

- [ ] Build script (`frontend/build.sh` or npm script)
  - [ ] Run `vite build`
  - [ ] Output to `lib/prompt_objects/server/public/`
  - [ ] Hash assets for cache busting
- [ ] Add built assets to gem (not gitignored in gem, but gitignored in dev)
- [ ] Verify assets load correctly when gem is installed
- [ ] Development vs production asset handling
  - [ ] Dev: Vite dev server with proxy
  - [ ] Prod: Serve from bundled assets

### Bundle Export/Import

- [ ] `prompt_objects export PATH` command
  - [ ] Creates .poenv zip bundle
  - [ ] `--output` / `-o` to specify output path
  - [ ] `--no-sessions` to exclude sessions.db
- [ ] `prompt_objects import BUNDLE` command
  - [ ] Extracts .poenv to directory
  - [ ] `--path` to specify destination
  - [ ] Warns if destination exists

### First-Run Experience

- [ ] `prompt_objects new NAME` creates new environment
  - [ ] `--template` option (minimal, developer, writer)
  - [ ] Creates directory with manifest, objects/, etc.
  - [ ] Prints next steps
- [ ] When serving empty environment, show helpful UI state
- [ ] Link to documentation in UI

### Gem Packaging

- [ ] Update gemspec to include server/ and public/ files
- [ ] Test gem build and install locally
- [ ] Test `gem install prompt_objects` from built gem
- [ ] Document installation in README

---

## CLI Reference

```bash
# Serve an environment
prompt_objects serve ./my-environment
prompt_objects serve ./my-environment --port 4000 --open

# Serve a bundle directly
prompt_objects serve my-agents.poenv

# Create new environment
prompt_objects new my-project
prompt_objects new my-project --template developer

# Export environment
prompt_objects export ./my-environment
prompt_objects export ./my-environment --output agents.poenv --no-sessions

# Import bundle
prompt_objects import agents.poenv
prompt_objects import agents.poenv --path ./imported-agents

# Existing commands still work
prompt_objects tui ./my-environment    # TUI mode
prompt_objects mcp ./my-environment    # MCP server mode
```

---

## File Structure After This Epic

```
prompt_objects.gemspec
lib/
├── prompt_objects.rb
└── prompt_objects/
    ├── cli.rb                    # Thor CLI with serve, export, import
    ├── server/
    │   ├── app.rb
    │   ├── websocket_handler.rb
    │   ├── api/
    │   │   └── routes.rb
    │   └── public/               # Built frontend assets (included in gem)
    │       ├── index.html
    │       └── assets/
    │           ├── main.abc123.js
    │           └── main.abc123.css
    └── ...

frontend/                         # Development only, not in gem
├── src/
├── package.json
└── build.sh
```

---

## Exit Criteria

```bash
# Clean install test
gem build prompt_objects.gemspec
gem install ./prompt_objects-*.gem

# Create and serve
prompt_objects new test-env --template minimal
prompt_objects serve ./test-env --open

# Browser opens, UI loads, can chat with POs

# Export and share
prompt_objects export ./test-env --output test.poenv
# Send test.poenv to colleague

# Import and run
prompt_objects import test.poenv --path ./imported
prompt_objects serve ./imported
```

---

## Technical Notes

### Gemspec Assets

```ruby
# prompt_objects.gemspec
spec.files = Dir[
  'lib/**/*',
  'exe/*',
  # Include built frontend
  'lib/prompt_objects/server/public/**/*'
]
```

### .gitignore Strategy

```gitignore
# During development, don't commit built assets
lib/prompt_objects/server/public/

# But the build script creates them before gem build
```

### Build Script

```bash
#!/bin/bash
# frontend/build.sh
cd "$(dirname "$0")"
npm ci
npm run build
# Vite outputs to ../lib/prompt_objects/server/public/
```

### Rake Task

```ruby
# Rakefile
task :build_frontend do
  sh 'cd frontend && npm ci && npm run build'
end

task :build => [:build_frontend] do
  sh 'gem build prompt_objects.gemspec'
end
```

---

## Related

- [web-ui-complete.md](web-ui-complete.md) - Previous epic
- [web-server-design.md](../web-server-design.md) - Full design document
