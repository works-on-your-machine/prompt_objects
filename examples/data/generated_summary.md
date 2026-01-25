# PromptObjects Framework Summary

The PromptObjects framework is a Ruby system that treats markdown files as autonomous entities powered by LLMs. Key characteristics:

- **Unified capability interface** – primitives and prompt objects use the same API.
- **YAML frontmatter** – configuration and metadata live at the top of each file.
- **Markdown body** – serves directly as the system prompt for the LLM.
- **Message bus tracking** – logs every message exchanged across components.
- **Human-in-the-loop** – prompts the user for confirmation when required.

---

> **Result**: a lightweight, extensible workflow for building self‑contained LLM‑driven agents in Ruby.
