# So What? The Case for Prompt Objects

## The Problem: Compounding Failure

Every system that chains AI services hits the same wall. If each step in a pipeline has a 90% success rate, the math is brutal:

| Steps | Overall Success Rate |
|-------|---------------------|
| 1     | 90%                 |
| 2     | 81%                 |
| 3     | 73%                 |
| 5     | 59%                 |
| 10    | 35%                 |

This is the fundamental problem with the current "agent" architecture: chain more tools, add more steps, and reliability plummets. Each link is a one-way gate. It either works or it doesn't, and failures propagate forward with no recourse.

The industry response has been to throw material at an architectural problem — better models, more tokens, faster inference, fancier guardrails. It doesn't work. You can't fix a structural issue with better materials.

## The Inversion: Compounding Recovery

Prompt Objects invert the topology. Instead of an open-loop pipeline where errors cascade forward, you get a closed-loop system with feedback at every node.

When a prompt object encounters a problem, it has multiple recovery paths — and they're all just more message-passing:

- **Try a different approach.** The PO reasons about what went wrong and adapts.
- **Create a new capability.** If the right tool doesn't exist, make one.
- **Modify itself.** If its own prompt isn't working for a task, change it.
- **Modify another object.** If a downstream PO is failing, fix it.
- **Ask for clarification.** Send a message back to the caller — or to the human.
- **Route around the problem.** Delegate to a different object entirely.

Instead of `P(success) = p1 × p2 × p3 × ...` (compounding failure), each step looks more like `P(failure) = p_fail × (1 - p_recover1) × (1 - p_recover2) × ...` — the recovery opportunities are what compound.

This isn't a guarantee. Recovery mechanisms have costs — latency, tokens, the possibility of making things worse. The claim isn't that it's free. The claim is that the architecture makes recovery **possible at every step**, where traditional chains make it structurally impossible. That's the meaningful difference.

## Why It's Simple

The other half of the argument: the recovery logic is **native to the medium**.

A prompt object asking for clarification, modifying its approach, or creating a new tool is just sending messages. It's the same thing it was already doing. There's no separate error-handling layer. No retry framework bolted on. No circuit breakers or fallback routing or orchestration layer.

If you tried to build equivalent recovery into a traditional service chain, you'd need all of that — and every piece is more code to maintain, more surface area for bugs. The recovery infrastructure itself becomes a source of compounding complexity.

With prompt objects, the recovery and the work are the same thing: natural language messages flowing between objects that can interpret, adapt, and respond. The "error handling" is just more conversation. One paradigm, not two.

This is a direct consequence of semantic late binding. The reason recovery is natural is *because* meaning is resolved at runtime. A PO doesn't need to know in advance every way something could go wrong — it interprets what happened and decides what to do next, the same way it handles any message.

## The Proof: ARC-AGI

People ask: "Ok great, but what does that actually get you? What can you build with this?"

The answer: something like ARC-AGI or AIMO — benchmarks specifically designed to test general reasoning and novel problem-solving.

**ARC-AGI is the perfect showcase.** Each puzzle requires discovering a novel transformation from a handful of examples. You can't memorize your way through it. This is exactly the scenario where the compounding recovery loop matters:

1. A prompt object looks at the examples and hypothesizes a transformation rule.
2. It **creates a primitive** to implement that rule.
3. It **tests the primitive** against the training examples.
4. It sees the primitive fails on example 3.
5. It **modifies its approach** — or creates a different primitive entirely.
6. It retests. Iterates. Recovers.

A static LLM call looks at the grid and guesses. A prompt object *builds tools and tests them*.

**The transparency is the kicker.** If a Python ML system scores well on ARC, people shrug — it's a black box. If a PromptObjects environment solves ARC puzzles and you can open it up and see the coordinator delegating to a pattern-recognizer, which creates a `grid_transform` primitive, tests it, sees it fail, modifies it, retests — that's *legible*. You can follow the reasoning in the message bus. You can watch the system think.

**Ruby is a feature, not a limitation.** It signals that this is about architecture, not GPU brute force. A small, readable system solving problems that massive ML pipelines struggle with.

## The Architecture Argument

Alan Kay, in "The Computer Revolution Hasn't Happened Yet":

> "We all know... that when you blow something up by a factor of 100, its mass goes up by a factor of a million, and its strength... only goes up by a factor of 10,000... And in fact what will happen to this doghouse is it will just collapse into a pile of rubble."

You can't scale a doghouse into a cathedral by using better wood. As complexity increases, architecture always dominates material.

The current AI agent ecosystem is building doghouses and hoping they scale. Chain more tools, add more steps, bolt on more guardrails — and it collapses under its own weight because the architecture can't bear the load.

Prompt Objects are an architectural bet. Message-passing between autonomous objects that negotiate meaning, self-modify, and compose dynamically — that's the kind of principle that scales. Adding more objects doesn't multiply failure. It multiplies recovery surface. The same architecture that handles a simple 3x3 grid transformation handles complex multi-step reasoning. The coordinator, the message bus, the self-modification loop — it's all the same. You just add more prompt objects.

## The Lineage

Kay was talking about Smalltalk, and nobody really listened. The vision was objects as autonomous entities that communicate through messages and negotiate meaning — computing as a living, inhabitable environment, not a static tool.

Ruby has always been the spiritual heir to that philosophy. Objects all the way down. Message-passing as the fundamental operation. The developer as an inhabitant of the system, not just a user of it.

LLMs accidentally provided the piece Smalltalk never had: a semantic runtime. An interpreter that doesn't just dispatch method calls but *understands and negotiates meaning*. The binding isn't just late — the meaning itself gets resolved at runtime.

Prompt Objects sit at the intersection of these three threads: Kay's architectural vision, Ruby's cultural commitment to expressiveness, and LLMs as the semantic interpreter that makes it all work. The computer revolution that Kay said hadn't happened yet? Maybe it starts with a markdown file that can talk back.
