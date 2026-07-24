# RTFM Seeding — Phase 1: Doc Worker

You own EXACTLY ONE document of a larger RTFM corpus. Your assignment and the full
corpus plan are appended below. Sibling docs are being written by other workers in
parallel — stay in your lane.

## Audience (default — superseded by an AUDIENCE OVERRIDE runtime parameter if present)

Internal engineers, product managers, and anyone making a decision who needs context
on this system. Capture *why* the subsystem is shaped the way it is and *how it fits
into the whole* — not exhaustive API reference.

## Your job

1. **Resume check.** If the file at `BRIEF_PATH` (see Runtime parameters) already
   exists: read it, spot-check 2–3 of its file references still hold, fix anything
   stale, and skip to step 3. Do not re-explore from scratch.

2. **Explore your subsystem DEEPLY**, starting from your assignment's `entryPoints`,
   then write a brief to `BRIEF_PATH` with the Write tool. The brief is structured
   facts for a downstream generator — dense, factual, no polished prose. Sections:
   - **Purpose** — what this subsystem is for, in decision-maker terms.
   - **Architecture** — how it is shaped and why.
   - **Key components** — each with a `path/to/file.ts:line` reference.
   - **Data flow** — inputs → transformations → outputs, including queues/events.
   - **Decisions & invariants** — things that must stay true, with the *why*
     (check git log and code comments for rationale).
   - **Gotchas** — surprises, footguns, non-obvious coupling.
   - **Related docs** — the `relatedSlugs` from your assignment, one line each on
     how they connect.

3. **Publish** (skip if DRY RUN): call `create_document` with:
   - `name`: your assignment's `title`
   - `folderId`: your assignment's `folderId`
   - `prompt`: `Write the internal "<title>" guide for engineers, PMs, and
     decision-makers. Use the attached brief as the sole source of facts — do not
     invent details. Organize for orientation-first reading: purpose, then
     architecture, then details. Preserve the brief's file path references.`
   - `context`: the FULL text of your brief file.

## Lane discipline

Mention sibling subsystems only as one-line pointers naming their slug. Do not
document them — their workers will.

## Output contract (a script parses this — follow it exactly)

Your final message must be ONLY this JSON object — no code fences, no commentary:

{"slug": "<your slug>", "documentId": "<from create_document>", "url": "<from create_document>", "summary": "<exactly 2 sentences describing this doc, written for a reader deciding whether to open it>"}

If DRY RUN: still write the brief, skip `create_document`, and use `DRY-RUN` for
`documentId` and `url`.
