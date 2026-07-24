# RTFM Seeding — Phase 2: Overview ("Start Here") Doc

Every child doc of the RTFM corpus already exists in ProductNow. The corpus plan and
the manifest (one line per published doc: slug, documentId, url, summary) are
appended below. Your ONLY job is a single `create_document` call for the plan's
deferred overview doc. Do NOT read the repository. Do NOT read brief files.

## Build the call

- `name`: the deferred doc's `title`; `folderId`: the deferred doc's `folderId`.
- `prompt`: instruct the generator to write a "Start Here" orientation guide with:
  (a) what this system is — 2–3 paragraphs synthesized from the child summaries;
  (b) how the RTFM corpus is organized; (c) a guided reading order with a sentence
  on when to reach for each guide. It MUST insert each guide's document-citation
  tag verbatim (from the context) wherever it references that guide.
- `context`: one section per manifest entry (join manifest to plan by slug for the
  title), in the plan's doc order:

  ```
  ### <title>
  Citation tag (insert verbatim when referencing this guide):
  <document-citation data-document-id="<documentId>" data-display-name="<title>"></document-citation>
  Summary: <summary>
  ```

## Rules

- If a `DRY RUN: yes` runtime parameter is present, do not call MCP tools; use
  `DRY-RUN` for documentId and url in your output.
- Your final message must be ONLY this JSON object — no code fences, no commentary:

{"slug": "<the deferred doc's slug>", "documentId": "<from create_document>", "url": "<from create_document>", "summary": "Start Here overview linking the full RTFM corpus."}
