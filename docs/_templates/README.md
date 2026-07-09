# Documentation templates

Skeletons for common ClickHouse doc types. Copy the relevant template, fill the
`{placeholders}`, and delete the guidance comments.

## Reference templates (`.md`)

Section snippets for reference content — paste into a page and adjust heading levels:

- `template-function.md`
- `template-server-setting.md`
- `template-engine.md`
- `template-system-table.md`
- `template-statement.md`

## Narrative templates

- `template-guide.mdx` — a full-page how-to / setup guide

## Filling in `template-guide.mdx`

The section order is fixed; drop a section only if it genuinely doesn't apply. The
author's job is to classify the content's *shape* — the shape dictates the component:

| Content shape | Component |
|---|---|
| Procedure with depth (screenshots, code, sub-steps) | `<Steps>` / `<Step>` with `### {#anchor}` headings |
| A step or section that differs by variant (provider, OS, deployment) | `<Tabs>` / `<Tab title="…" id="…">` — the `id` makes a variant deep-linkable via `#id` |
| Selective-consult content — the reader wants one item (Troubleshooting, FAQ) | `<Accordion title="…">`, one per item |
| Advisory list read in full (Best practices) | `### {#anchor}` subheadings, one per item |
| Matrix — the reader scans a column *down* to compare values (action→result, source→target mappings) | markdown table |
| Callout | `<Note>` / `<Warning>` / `<Tip>` |

Guidelines:

- **How it works** goes *before* the steps and describes the end-to-end *flow* (what
  happens, in order) — not behavioral or reference detail, which belongs in FAQ.
- The main procedure can be **one or several `## {Task}` sections**.
- **Verify**, **Best practices**, and **FAQ** are prompts as much as sections: include
  them when there's real content to add; don't fabricate to fill them.
- Frontmatter uses `sidebarTitle` (no repeated `# H1`). Built-in components (`Steps`,
  `Accordion`, `Tabs`, `Note`, `Warning`, `Tip`) need no import.
- Every `##` / `###` needs a unique `{#anchor}`.
