# ARC-AGI: Other Approaches (For Context)

What others have tried. Not a roadmap for us — just useful to know what the landscape looks like.

## Leaderboard Snapshot

| Approach | ARC-AGI-1 Score | Method |
|----------|-----------------|--------|
| OpenAI o3 (high compute) | 87.5% | Massive test-time compute, internal chain-of-thought |
| MindsAI | 55.5% | Test-time fine-tuning + data augmentation |
| ARChitects | 53.5% | Fine-tuned 8B model + augmentation ensembling |
| SOAR | 52% | Evolutionary program synthesis with self-improving LLMs |
| Greenblatt (GPT-4o) | ~50% | LLM-guided Python program generation + iterative debugging |
| Claude Opus 4.5 (Thinking) | 37.6% | Direct reasoning with extended thinking |
| Claude 3.5 Sonnet | 14% | Direct prompting |
| GPT-4o (direct) | 5% | Direct prompting, no scaffolding |

The gap between GPT-4o direct (5%) and GPT-4o with Greenblatt's scaffolding (50%) is the most telling number. The scaffolding matters more than the model.

## Key Approaches

### Program Synthesis (Greenblatt)
Generate ~8,000 Python programs per task via LLM, run each against training examples, keep the ones that produce correct output. An iterative debugging step (show the LLM its wrong output vs expected with a diff) contributed 13% absolute improvement and reduced sample requirements by ~12x. Built in ~6 days.

### Test-Time Training (MindsAI, ARChitects)
Fine-tune model weights at test time on each specific task. Use data augmentation (rotations, reflections, color permutations) to expand the 2-3 training examples into many. The model literally trains on each puzzle before solving it.

### Evolutionary Search (SOAR)
Maintain a population of candidate programs, use LLM to generate variations, select the best performers. The interesting bit: they use *all* search traces (successes AND failures) as training data by relabeling failed programs as correct solutions for whatever synthetic tasks they happen to solve. Nearly doubled performance over iterations.

### Refinement Harness (Poetiq — current SOTA on ARC-AGI-2)
Application-layer loop: generate candidate, verify against training examples, show the LLM structured feedback (including diffs), LLM refines. Improved Gemini 3 Pro from 31% to 54% on ARC-AGI-2 through the harness alone. Model-agnostic — works across providers.

### Brute-Force DSL (Icecuber, classic)
Hand-craft a domain-specific language of ~142 grid operations, exhaustively search combinations up to depth 4. No LLM involved. The intelligence is in DSL design. Still competitive with early LLM approaches.

## ARC-AGI-2 (The Harder Version)

Released 2025. Designed to resist the approaches that worked on AGI-1:
- Systems that scored 50%+ on AGI-1 dropped to single digits on AGI-2
- Multiple interacting rules per task (not just one transformation)
- Adversarially designed against brute-force search
- Mandatory cost-per-task reporting

Best scores on AGI-2: Poetiq at 54% ($31/task), Gemini Deep Think at 45% ($77/task), NVARC at 24% ($0.20/task).

## What's Interesting For Us

Most of these are **generate many candidates, verify, refine the best failures**. The verification + structured feedback loop is the common thread across all top approaches. That maps naturally to what POs already do — the solver reasons, builds a primitive, tests it, sees the diff, and iterates.

The self-improvement pattern in SOAR (learning from all attempts, not just successes) is philosophically aligned with the compounding recovery thesis — every attempt, successful or not, makes the system more capable.

But the key difference in our approach: we're not building a fixed pipeline. We're building an environment where the solving strategy itself can emerge and evolve. The solver might discover program synthesis on its own. Or it might find something different. That's the point.

## Sources

- [ARC Prize Leaderboard](https://arcprize.org/leaderboard)
- [Greenblatt: Getting 50% on ARC-AGI with GPT-4o](https://blog.redwoodresearch.org/p/getting-50-sota-on-arc-agi-with-gpt)
- [ARC Prize 2024 Technical Report](https://arcprize.org/blog/arc-prize-2024-winners-technical-report)
- [ARC Prize 2025 Results](https://arcprize.org/blog/arc-prize-2025-results-analysis)
- [SOAR (arXiv)](https://arxiv.org/abs/2507.14172)
- [Poetiq ARC-AGI Solver](https://github.com/poetiq-ai/poetiq-arc-agi-solver)
