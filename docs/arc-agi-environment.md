# ARC-AGI-1: PromptObjects Environment Design

The goal isn't to replicate existing ARC approaches. The goal is to let Prompt Objects do what they do — receive messages, reason, create tools, modify themselves, ask for help — and see what emerges when pointed at ARC tasks.

## Philosophy

We seed the environment with the minimum viable set of POs and primitives. The system should discover what it needs and build it. If we over-engineer the starting state, we're doing the same thing as everyone else — just with markdown files instead of Python scripts. The interesting question is: **what does the system create for itself?**

The starting environment should give the system:
1. A way to **see** the grids (render them in a format the LLM can reason about)
2. A way to **manipulate** grids (basic operations it can compose)
3. A way to **test** its ideas (validate against training examples)
4. A way to **build new tools** when what it has isn't enough

Everything else — strategy, decomposition, what to look for — should come from the POs themselves.

## Initial Prompt Objects

### `solver.md` — The Entry Point

The solver receives a task and figures out how to solve it. It has access to grid primitives and the universal capabilities (think, create_primitive, create_capability, ask_human, etc.). We don't tell it *how* to solve — we tell it what success looks like.

```markdown
---
name: solver
description: Solves ARC-AGI tasks by studying examples, forming hypotheses, building and testing transformations
capabilities:
  - load_arc_task
  - render_grid
  - grid_diff
  - grid_info
  - find_objects
  - grid_transform
  - test_solution
---

# Solver

## Identity

You solve ARC-AGI tasks. Each task shows you a few input/output grid pairs that demonstrate a transformation rule. Your job is to figure out the rule and apply it to a new test input.

## What You Have

You have primitives for loading tasks, rendering grids, comparing grids, finding objects, and applying basic transforms. You also have universal capabilities — you can create new primitives when you need tools that don't exist yet, and you can ask the human for help when you're stuck.

## What Success Looks Like

Your output grid must be an exact cell-by-cell match with the expected output. Close doesn't count. If your solution works on all training pairs, apply it to the test input.

## How to Work

Look at the examples. Really look at them — render the grids, diff the inputs and outputs, find the objects, check the dimensions. Form a theory about what's happening. Build a way to test that theory. If it doesn't work, look at exactly where it fails and use that information.

You have two attempts per test input. If your first attempt fails validation on training pairs, use what you learned from the failure to improve.

If you need a tool that doesn't exist, create it. If you're stuck after multiple attempts, ask the human — even a small hint can unlock the whole problem.
```

That's it. One PO. It has the tools, it has the universal capabilities, and it has a clear objective. If it needs to decompose the problem — delegate to a pattern analyzer, create a hypothesis generator — it can do that itself via `create_capability`. But we don't assume it needs to.

### Why Not Start with Multiple Specialist POs?

Because that's us imposing a strategy. Maybe the solver creates specialists. Maybe it doesn't — maybe it just reasons through problems directly and creates primitives as needed. Maybe it creates different specialists for different *types* of tasks. The point is: **let the architecture work**. If we pre-build a "pattern_analyst" and a "hypothesis_generator" and a "verifier", we've already decided the strategy. That's the doghouse approach.

If after running a bunch of tasks we see the solver consistently creating the same kinds of helpers, *then* we can seed them as starting POs in a v2 environment.

## Initial Primitives

These are the mechanical operations the solver needs to see and manipulate grids. They're deterministic Ruby — no LLM reasoning in here.

### `load_arc_task`
Parse an ARC task JSON file into structured data with training pairs and test inputs.

```ruby
module PromptObjects::Primitives
  class LoadArcTask < Primitive
    def name = "load_arc_task"
    def description = "Load an ARC task from a JSON file path. Returns training pairs and test inputs."

    def parameters
      {
        type: "object",
        properties: {
          path: { type: "string", description: "Path to the ARC task JSON file" }
        },
        required: ["path"]
      }
    end

    def receive(message, context:)
      path = message[:path] || message["path"]
      data = JSON.parse(File.read(path, encoding: "UTF-8"))

      result = {
        training_pairs: data["train"].length,
        test_inputs: data["test"].length,
        train: data["train"].map.with_index { |pair, i|
          {
            pair: i,
            input: pair["input"],
            output: pair["output"],
            input_size: "#{pair["input"].length}x#{pair["input"][0].length}",
            output_size: "#{pair["output"].length}x#{pair["output"][0].length}"
          }
        },
        test: data["test"].map.with_index { |t, i|
          {
            test: i,
            input: t["input"],
            input_size: "#{t["input"].length}x#{t["input"][0].length}"
          }
        }
      }

      JSON.pretty_generate(result)
    end
  end
end
```

### `render_grid`
Display a grid as readable text. This is how the LLM "sees" the grid.

```ruby
module PromptObjects::Primitives
  class RenderGrid < Primitive
    SYMBOLS = { 0 => ".", 1 => "1", 2 => "2", 3 => "3", 4 => "4",
                5 => "5", 6 => "6", 7 => "7", 8 => "8", 9 => "9" }

    def name = "render_grid"
    def description = "Render an ARC grid as readable text with coordinates. 0/background shown as dots."

    def parameters
      {
        type: "object",
        properties: {
          grid: { type: "array", description: "2D array of integers 0-9" },
          label: { type: "string", description: "Optional label" }
        },
        required: ["grid"]
      }
    end

    def receive(message, context:)
      grid = message[:grid] || message["grid"]
      label = message[:label] || message["label"]
      rows = grid.length
      cols = grid[0]&.length || 0

      lines = []
      lines << label if label
      lines << "#{rows}x#{cols}"

      col_header = "   " + (0...cols).map { |c| c.to_s.rjust(2) }.join
      lines << col_header
      lines << "   " + "--" * cols

      grid.each_with_index do |row, r|
        cells = row.map { |v| (SYMBOLS[v] || "?").rjust(2) }.join
        lines << "#{r.to_s.rjust(2)}|#{cells}"
      end

      lines.join("\n")
    end
  end
end
```

### `grid_diff`
Compare two grids cell by cell. This is how the solver sees *what changed*.

```ruby
module PromptObjects::Primitives
  class GridDiff < Primitive
    def name = "grid_diff"
    def description = "Compare two grids cell by cell. Shows which cells differ with coordinates and values."

    def parameters
      {
        type: "object",
        properties: {
          grid_a: { type: "array", description: "First grid" },
          grid_b: { type: "array", description: "Second grid" }
        },
        required: ["grid_a", "grid_b"]
      }
    end

    def receive(message, context:)
      a = message[:grid_a] || message["grid_a"]
      b = message[:grid_b] || message["grid_b"]

      if a.length != b.length || a[0]&.length != b[0]&.length
        return "DIMENSION MISMATCH: #{a.length}x#{a[0]&.length} vs #{b.length}x#{b[0]&.length}"
      end

      diffs = []
      matching = 0
      total = a.length * a[0].length

      a.each_with_index do |row, r|
        row.each_with_index do |val, c|
          if val == b[r][c]
            matching += 1
          else
            diffs << "(#{r},#{c}): #{val} -> #{b[r][c]}"
          end
        end
      end

      lines = ["#{matching}/#{total} cells match (#{diffs.length} differ)"]
      if diffs.empty?
        lines << "IDENTICAL"
      else
        diffs.first(30).each { |d| lines << "  #{d}" }
        lines << "  ... and #{diffs.length - 30} more" if diffs.length > 30
      end
      lines.join("\n")
    end
  end
end
```

### `grid_info`
Basic metadata about a grid — dimensions, color counts, density.

```ruby
module PromptObjects::Primitives
  class GridInfo < Primitive
    def name = "grid_info"
    def description = "Get grid dimensions, color frequencies, and density."

    def parameters
      {
        type: "object",
        properties: {
          grid: { type: "array", description: "2D array of integers" }
        },
        required: ["grid"]
      }
    end

    def receive(message, context:)
      grid = message[:grid] || message["grid"]
      flat = grid.flatten
      colors = flat.tally.sort.to_h

      JSON.pretty_generate({
        rows: grid.length,
        cols: grid[0]&.length || 0,
        total_cells: flat.length,
        colors: colors,
        non_background: flat.count { |c| c != 0 }
      })
    end
  end
end
```

### `find_objects`
Connected component detection — find distinct objects in the grid.

```ruby
module PromptObjects::Primitives
  class FindObjects < Primitive
    def name = "find_objects"
    def description = "Find connected objects (same-color adjacent cells) in a grid. Returns object list with bounding boxes and cell counts."

    def parameters
      {
        type: "object",
        properties: {
          grid: { type: "array", description: "2D array of integers" },
          background: { type: "integer", description: "Background color to ignore (default: 0)" }
        },
        required: ["grid"]
      }
    end

    def receive(message, context:)
      grid = message[:grid] || message["grid"]
      bg = message[:background] || message["background"] || 0
      rows = grid.length
      cols = grid[0]&.length || 0
      visited = Array.new(rows) { Array.new(cols, false) }
      objects = []

      rows.times do |r|
        cols.times do |c|
          next if visited[r][c] || grid[r][c] == bg
          color = grid[r][c]
          cells = []
          queue = [[r, c]]
          visited[r][c] = true
          while (pos = queue.shift)
            cr, cc = pos
            cells << [cr, cc]
            [[-1,0],[1,0],[0,-1],[0,1]].each do |dr, dc|
              nr, nc = cr + dr, cc + dc
              next if nr < 0 || nr >= rows || nc < 0 || nc >= cols
              next if visited[nr][nc] || grid[nr][nc] != color
              visited[nr][nc] = true
              queue << [nr, nc]
            end
          end
          rs = cells.map(&:first)
          cs = cells.map(&:last)
          objects << {
            color: color, cells: cells.length,
            bounds: { top: rs.min, left: cs.min, bottom: rs.max, right: cs.max }
          }
        end
      end

      JSON.pretty_generate({ objects: objects })
    end
  end
end
```

### `grid_transform`
Basic geometric operations — rotate, flip, transpose, crop.

```ruby
module PromptObjects::Primitives
  class GridTransform < Primitive
    def name = "grid_transform"
    def description = "Apply geometric transforms: rotate_90, rotate_180, rotate_270, flip_h, flip_v, transpose."

    def parameters
      {
        type: "object",
        properties: {
          grid: { type: "array", description: "2D array of integers" },
          operation: { type: "string", enum: %w[rotate_90 rotate_180 rotate_270 flip_h flip_v transpose] }
        },
        required: ["grid", "operation"]
      }
    end

    def receive(message, context:)
      grid = message[:grid] || message["grid"]
      result = case message[:operation] || message["operation"]
        when "rotate_90"  then grid.transpose.map(&:reverse)
        when "rotate_180" then grid.reverse.map(&:reverse)
        when "rotate_270" then grid.transpose.reverse
        when "flip_h"     then grid.map(&:reverse)
        when "flip_v"     then grid.reverse
        when "transpose"  then grid.transpose
      end
      JSON.generate(result)
    end
  end
end
```

### `test_solution`
The critical one — run a candidate solution against all training pairs.

```ruby
module PromptObjects::Primitives
  class TestSolution < Primitive
    def name = "test_solution"
    def description = "Test a transformation primitive against ARC training pairs. Runs it on each input and checks for exact match with expected output."

    def parameters
      {
        type: "object",
        properties: {
          primitive_name: { type: "string", description: "Name of the primitive to test" },
          train: { type: "array", description: "Training pairs with input/output grids" }
        },
        required: ["primitive_name", "train"]
      }
    end

    def receive(message, context:)
      prim_name = message[:primitive_name] || message["primitive_name"]
      train = message[:train] || message["train"]

      primitive = context.env.registry.get(prim_name)
      return "Error: '#{prim_name}' not found" unless primitive

      results = []
      passed = 0

      train.each_with_index do |pair, i|
        input = pair["input"] || pair[:input]
        expected = pair["output"] || pair[:output]

        begin
          actual = primitive.receive({ grid: input }, context: context)
          actual = JSON.parse(actual) if actual.is_a?(String)

          if actual == expected
            passed += 1
            results << "Pair #{i}: PASS"
          else
            wrong = 0
            [expected.length, actual.length].min.times do |r|
              [expected[0].length, actual[0]&.length || 0].min.times do |c|
                wrong += 1 if actual[r][c] != expected[r][c]
              end
            end
            dim_match = actual.length == expected.length && actual[0]&.length == expected[0]&.length
            results << "Pair #{i}: FAIL (#{wrong} cells wrong, dimensions #{dim_match ? 'match' : 'MISMATCH'})"
          end
        rescue => e
          results << "Pair #{i}: ERROR — #{e.message}"
        end
      end

      "#{passed}/#{train.length} passed\n" + results.join("\n")
    end
  end
end
```

## What's NOT in the Starting Environment

- No "pattern analyzer" PO — the solver can reason about patterns itself, or create one if it wants to
- No "hypothesis generator" PO — the solver forms its own hypotheses
- No DSL — the solver creates primitives as needed, building up its own vocabulary
- No pre-built solution strategies — the solver decides how to approach each task
- No batch runner — start with one task at a time, build automation later if needed

## The Interesting Questions

Once the environment is running, we watch what happens:

1. **What primitives does the solver create?** After 10 tasks, what's in the registry that wasn't there at the start? That's the system building its own DSL.

2. **Does the solver create other POs?** If it does, what roles do they play? That's the system discovering its own architecture.

3. **Does the solver modify itself?** After failing tasks, does it add heuristics or strategies to its own prompt? That's the system learning.

4. **Where does it ask for help?** The `ask_human` calls tell us where the system's reasoning breaks down. That's the most interesting data.

5. **Do primitives accumulate?** After 50 tasks, is the solver faster/better because of tools it built earlier? That's the compounding recovery thesis in action.

## Running It

```bash
# Clone ARC data
git clone https://github.com/fchollet/ARC-AGI.git data/arc-agi

# Point the solver at a task
# (from the PO web UI, send a message to solver)
> Solve the task at data/arc-agi/data/training/007bbfb7.json
```

Start with easy tasks (the training set roughly goes from easier to harder by filename). Watch the message bus. See what the solver does. Iterate on the environment based on what you observe, not on what you think it should need.
