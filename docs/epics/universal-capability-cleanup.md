# Universal Capability Cleanup — Consolidate Primitive Management Surface

**Status**: Ready
**Priority**: Medium (after Shared Environment Data ships)
**Depends on**: None (standalone refactor)

---

## Problem

The universal capabilities list has grown to 14 entries, with 7 dedicated to primitive management. Several overlap with the generic capability management surface, and three share duplicated code generation and syntax validation logic.

This matters because every universal capability appears in the tool list for every LLM call. 14 tools is manageable; adding 5 more for shared environment data pushes it to 19. Consolidation keeps the tool surface lean and reduces LLM confusion about which tool to pick.

### Current Inventory (14)

| # | Capability | Group |
|---|---|---|
| 1 | `ask_human` | Core |
| 2 | `think` | Core |
| 3 | `modify_prompt` | Core |
| 4 | `create_capability` | Capability CRUD |
| 5 | `add_capability` | Capability CRUD |
| 6 | `remove_capability` | Capability CRUD |
| 7 | `list_capabilities` | Capability CRUD |
| 8 | `create_primitive` | Primitive CRUD |
| 9 | `add_primitive` | Primitive CRUD |
| 10 | `delete_primitive` | Primitive CRUD |
| 11 | `modify_primitive` | Primitive CRUD |
| 12 | `verify_primitive` | Primitive CRUD |
| 13 | `list_primitives` | Primitive CRUD |
| 14 | `request_primitive` | Primitive CRUD |

### Overlap Map

| Generic | Primitive-specific | Difference |
|---|---|---|
| `create_capability` | `create_primitive` | `create_capability` handles both POs and primitives; `create_primitive` has better code generation |
| `add_capability` | `add_primitive` | `add_primitive` has nicer error messages for primitives |
| `list_capabilities(type: "primitives")` | `list_primitives` | `list_primitives` has granular filters (stdlib/custom/active/available) |
| `remove_capability` | `delete_primitive` | `delete_primitive` also removes the file from disk |
| — | `modify_primitive` | Unique (no generic equivalent) |
| — | `verify_primitive` | Unique (no generic equivalent) |
| — | `request_primitive` | Specialized `ask_human` for primitive approval |

---

## Proposed Consolidation

### Keep (3 core + 4 consolidated + 2 unique = 9 total)

| # | Capability | Notes |
|---|---|---|
| 1 | `ask_human` | Unchanged |
| 2 | `think` | Unchanged |
| 3 | `modify_prompt` | Unchanged |
| 4 | `create_capability` | Absorb `create_primitive` code generation; add `type` param (po/primitive) |
| 5 | `add_capability` | Absorb `add_primitive` UX improvements |
| 6 | `remove_capability` | Absorb `delete_primitive` file deletion for primitives |
| 7 | `list_capabilities` | Absorb `list_primitives` filters; add `filter` param |
| 8 | `modify_primitive` | Keep as-is (unique, no generic equivalent) |
| 9 | `verify_primitive` | Keep as-is (unique, no generic equivalent) |

### Remove (5)

| Capability | Absorbed into |
|---|---|
| `create_primitive` | `create_capability` |
| `add_primitive` | `add_capability` |
| `delete_primitive` | `remove_capability` |
| `list_primitives` | `list_capabilities` |
| `request_primitive` | `create_capability` (add approval flow when human confirmation needed) |

### Net result: 14 → 9 universals

With 5 env data capabilities added: 9 + 5 = 14 total (same count, better organized).

---

## Shared Code Extraction

Three capabilities currently duplicate syntax validation and code generation:

```ruby
# Duplicated in: create_primitive, request_primitive, modify_primitive
def validate_syntax(code)
  eval("proc { #{code} }")
  nil
rescue SyntaxError => e
  e.message.sub(/^\(eval\):\d+: /, "")
rescue StandardError
  nil
end
```

Extract to:

```ruby
# lib/prompt_objects/universal/primitive_support.rb
module PromptObjects
  module Universal
    module PrimitiveSupport
      def validate_syntax(code)
        eval("proc { #{code} }")
        nil
      rescue SyntaxError => e
        e.message.sub(/^\(eval\):\d+: /, "")
      rescue StandardError
        nil
      end

      def generate_primitive_class(class_name:, name:, description:, parameters:, code:)
        # Unified template used by create_capability and modify_primitive
      end
    end
  end
end
```

---

## Bug Fix (do first)

`delete_primitive.rb` line 52 references bare `UNIVERSAL_CAPABILITIES` — should be `::PromptObjects::UNIVERSAL_CAPABILITIES`. This will raise `NameError` at runtime if a PO tries to delete a universal capability. Fix this regardless of whether the full consolidation happens.

---

## Implementation Order

1. **Fix the bug** in `delete_primitive.rb` (5 min)
2. **Extract `PrimitiveSupport` module** with shared validation/generation
3. **Consolidate `list_capabilities` + `list_primitives`** (lowest risk, most visible improvement)
4. **Consolidate `add_capability` + `add_primitive`**
5. **Consolidate `remove_capability` + `delete_primitive`**
6. **Consolidate `create_capability` + `create_primitive` + `request_primitive`** (most complex — merge code generation and add approval flow)
7. **Update CLAUDE.md** universal capabilities list
8. **Update tests**

---

## Open Questions

1. **Should `modify_primitive` and `verify_primitive` become generic?** E.g., `modify_capability` that works for both POs (modify_prompt) and primitives (modify code)? Probably not — modifying a PO prompt vs modifying Ruby code are fundamentally different operations.
2. **Will LLMs adapt?** Existing PO prompts may reference `create_primitive` by name. We'd need to verify that LLMs can discover the consolidated `create_capability` with a `type: "primitive"` parameter. Probably fine — the description matters more than the name.
