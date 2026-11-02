---
name: lifeos-memory-action
description: Design or improve an in-app AI assistant that remembers conversations, retrieves personal records, and performs user-requested changes to study plans or schedules. Use when adding grounded memory, record search, targeted edits, or undoable AI tool calls to a life-management app.
---

# LifeOS Memory & Action

Build an assistant that can connect a person's request to real records and, when authorized, carry out a specific change. A skill supplies development guidance; the host app must implement the storage, permissions, and callable tools. Never report an action as completed until the host confirms its result.

## Workflow

1. Inspect the app's models, storage, existing AI integration, authorization settings, and tests. Identify which requested capabilities already work and which need implementation. Follow the app's established design and data semantics.
2. For memory, preserve the original conversation separately from a compact search index. Retrieve relevant evidence with dates and source references; handle pagination and empty or ambiguous results. Do not claim a memory was found when search returned none. Avoid sending more private context to a model provider than is needed and authorized.
3. For actions, translate the user's request into a bounded operation: record type, target identity or topic, date range and timezone, and exact changes. Resolve references from actual records rather than guessing. Preserve unrelated and completed records unless the user explicitly includes them. Ask only when information required to perform the requested action safely cannot be resolved.
4. Connect real host-side tools with validated input and structured success or failure results. Check permissions in the host, use stable IDs where possible, process all matching pages, and enforce bounds independently of the model. Perform related changes atomically where supported. For replacements or deletions, provide a recoverable snapshot or the app's existing undo mechanism and prevent rollback from overwriting later edits.
5. Test using synthetic data before touching real records. Cover mixed topics, boundary dates, pagination, repeated requests, partial failures, and undo after later edits. Verify the app's actual tool integration as well as its underlying storage. Distinguish local or mock tests from provider and device tests in the result.

For implementation patterns, read [references/implementation.md](references/implementation.md). Adapt the patterns to the target app; they are not preinstalled integrations.
