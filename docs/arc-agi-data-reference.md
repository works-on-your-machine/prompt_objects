# ARC-AGI-1: Data Reference

Everything you need to pull down the challenge set, parse it, and validate solutions.

## Getting the Data

**GitHub repo:** https://github.com/fchollet/ARC-AGI (Apache 2.0)

```bash
git clone https://github.com/fchollet/ARC-AGI.git
```

**Structure:**
```
ARC-AGI/
├── data/
│   ├── training/      # 400 task JSON files
│   └── evaluation/    # 400 task JSON files
└── apps/
    └── testing_interface.html  # Browser-based manual solver
```

Each task is a single JSON file named by an 8-character hex ID (e.g., `007bbfb7.json`).

## Task Format

```json
{
  "train": [
    {"input": [[0, 7, 7], [7, 7, 7], [0, 7, 7]], "output": [[0, 0, 0, 0, 7, 7, ...], ...]},
    {"input": [[...]], "output": [[...]]}
  ],
  "test": [
    {"input": [[7, 0, 7], [7, 0, 7], [7, 7, 0]], "output": [[...]]}
  ]
}
```

- **Grids** are 2D arrays of integers 0-9
- **Grid size** ranges from 1x1 to 30x30
- **Input and output can be different dimensions** — the solver must figure out the right output size
- **Training pairs** (2-10, typically 3): demonstrate the transformation by example
- **Test pairs** (1-3, typically 1): solver must produce the output from just the input
- The `output` field exists in the test data for evaluation, but the solver only sees the `input`

## Color Mapping

| Value | Color   |
|-------|---------|
| 0     | Black (typically background) |
| 1     | Blue    |
| 2     | Red     |
| 3     | Green   |
| 4     | Yellow  |
| 5     | Grey    |
| 6     | Magenta |
| 7     | Orange  |
| 8     | Cyan    |
| 9     | Maroon  |

Colors are just for visualization. The data is integers. Color 0 is *usually* background but not always.

## Evaluation

- **Exact match only.** Every cell and the grid dimensions must be identical. No partial credit.
- **2 attempts allowed** per test input (Kaggle competition rules; the browser UI allows 3).
- **Score** = number of correctly solved test outputs / total test outputs.
- **Human baseline**: ~73-85% accuracy.

## Dataset Splits

| Split      | Tasks | Notes |
|------------|-------|-------|
| Training   | 400   | `data/training/` — develop and iterate against these |
| Evaluation | 400   | `data/evaluation/` — hold out for final testing |

The Kaggle competition has additional semi-private and private splits (120 tasks each) that aren't publicly available.

## Loading in Ruby

```ruby
require 'json'

task = JSON.parse(File.read("data/training/007bbfb7.json"))

task["train"].each_with_index do |pair, i|
  input  = pair["input"]   # Array<Array<Integer>>
  output = pair["output"]   # Array<Array<Integer>>
  puts "Pair #{i}: #{input.length}x#{input[0].length} -> #{output.length}x#{output[0].length}"
end

task["test"].each_with_index do |t, i|
  input = t["input"]
  expected = t["output"]  # for validation
  puts "Test #{i}: #{input.length}x#{input[0].length}"
end
```

No special libraries needed. It's just JSON with nested arrays of small integers.

## What Makes ARC Hard

Each task embodies a *novel* transformation rule. You can't memorize patterns from a training set — you have to figure out the rule from 2-3 examples and apply it to a new input. The tasks assume only basic cognitive priors: objects exist, objects persist, basic geometry (symmetry, rotation), simple counting, topology (containment, adjacency).

## Concrete Example

Task `25ff71a9.json` — "gravity" (objects shift down one row):

```json
{
  "train": [
    {"input": [[1,1,1],[0,0,0],[0,0,0]], "output": [[0,0,0],[1,1,1],[0,0,0]]},
    {"input": [[0,0,0],[1,1,1],[0,0,0]], "output": [[0,0,0],[0,0,0],[1,1,1]]},
    {"input": [[0,1,0],[1,1,0],[0,0,0]], "output": [[0,0,0],[0,1,0],[1,1,0]]}
  ],
  "test": [
    {"input": [[2,0,0],[2,0,0],[0,0,0]], "output": [[0,0,0],[2,0,0],[2,0,0]]}
  ]
}
```

Note: this task has a simple rule, but many tasks involve complex compositions of multiple operations.
