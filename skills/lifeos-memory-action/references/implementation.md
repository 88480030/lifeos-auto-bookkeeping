# Implementation patterns

## Memory and retrieval

- Keep source messages durable and distinguish them from summaries and search indexes. Index rebuilds must not delete conversation history.
- Retrieve by relevance, recency, and source identity; return enough context to interpret a hit. Make empty results explicit. Exercise Chinese paraphrases, dates, and edits in tests if the app supports them.
- Report a truncated result and fetch subsequent pages before calling a result complete. Apply requested filters before pagination.

## Scoped record actions

- Expose separate read and mutation capabilities through the host's tool interface. A provider's function-calling response is a request to the host, not proof that the operation happened.
- Include the user's stated category, dates, selected topic or record IDs, and any excluded items in the host's validation. For calendar days, use the app's timezone and a documented interval convention. Distinguish planned date from creation date.
- A request such as “replace the guide-script tasks between two dates with one per day; leave English alone” needs all matching unfinished guide-script tasks in that range, not an entire day's tasks. Preserve completed items unless the request says otherwise. If precise content or time cannot be determined, preserve an existing time where appropriate and report any missing details.
- Apply explicit exclusions before matching: an item that matches both the target and an excluded topic should be preserved when its scope is unclear. When completed records already exist, distinguish “one new task” from “one total task” and avoid silently producing duplicate daily totals.
- For related multi-record changes, save a complete recoverable snapshot and commit the change atomically where the storage layer supports it. Guard against duplicates and retries. Undo should stop with an explanation if the affected records have changed since the operation.
- Report the actual affected count, range, and any unresolved details. Keep raw user messages and private records out of logs and test fixtures.

## Verification

Use an isolated store with several dates, multiple matching records per day, completed items, and unrelated categories. Check the exact before/after records, not just an AI response. Test pagination past the first page, invalid or overly broad inputs, transaction failure, safe retry, and undo conflict. A local test does not establish that a real provider selected the tool, that a device installed the build, or that a user's records changed.
