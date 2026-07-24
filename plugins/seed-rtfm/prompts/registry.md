# RTFM Seeding — Phase 3: Publish Changelog + Registry

The RTFM corpus (child docs + Start Here overview) already exists in ProductNow.
Your job is to publish the corpus's machine-readable state into ProductNow so
that scheduled update runs — which execute in CI with no local state — can find
and maintain the corpus. Do NOT read the repository.

## Step 1 — Create the changelog doc

Call `create_document` with:
- `name`: `RTFM Changelog`
- `folderId`: the root folder id (Runtime parameters below)
- `prompt`: `Create a changelog document that accumulates one entry per
  automated RTFM update run, newest first. Write only: a one-paragraph intro
  explaining that entries below are appended by automated maintenance runs, then
  a first entry titled "Seeded" dated today stating the RTFM corpus was created
  from the codebase.`

Record the returned documentId.

## Step 2 — Create the registry doc

Take the Registry JSON appended below, replace the placeholder string
`CHANGELOG_DOCUMENT_ID` with the documentId from Step 1, and call
`create_document` with:
- `name`: `RTFM Registry`
- `folderId`: the root folder id
- `prompt`: `This document is machine-read state for automated RTFM
  maintenance. Its entire body must be exactly the JSON provided in the attached
  context, rendered as a single fenced json code block — no headings, no prose,
  no commentary, and no changes to the JSON itself. Do not edit this document
  manually.`
- `context`: the full substituted JSON

## Step 3 — Verify the round-trip

Call `get_document` on the registry doc. Confirm its body contains the JSON,
that it parses, and that its `docs` array has the same number of entries as the
input JSON. If anything is wrong, correct it once: call
`switch_document_chat_edit_mode` (edit mode) then `post_document_chat_message`
instructing an exact full replacement of the body with the correct JSON code
block, then verify again with `get_document`.

## Output contract (a script parses this — final message is ONLY this JSON)

{"slug": "rtfm-registry", "registryDocumentId": "<id>", "changelogDocumentId": "<id>", "verified": true}

Set `"verified": false` only if the round-trip still fails after your one
corrective edit.
