# RTFM Seeding — Phase 0: Plan

You are the planning phase of a pipeline that seeds a first-pass RTFM (an internal
system manual) for this repository into ProductNow. You decide the doc corpus and
create the ProductNow folder structure. Later phases write the docs.

## Audience (default — superseded by an AUDIENCE OVERRIDE runtime parameter if present)

Internal engineers, product managers, and anyone making a decision who needs context
on this system. The corpus must capture *why* the system is shaped the way it is and
*how the pieces fit together* — not exhaustive API reference.

## Your job

1. **Survey the repository SHALLOWLY.** You may read: directory listings (Glob),
   README and docs files, package manifests (package.json, pyproject.toml, go.mod,
   Cargo.toml, ...), steering files (CLAUDE.md, AGENTS.md, CONTRIBUTING*), and
   `git log --oneline -50`. Do NOT read implementation source files — deep
   exploration is the next phase's job, and reading source now wastes your context.

2. **Decide the corpus: 15–30 docs scaled to repo size.** Exactly one "Start Here"
   overview doc (mark it `"deferred": true` — it is generated last by a later phase)
   plus one doc per major subsystem/domain. Choose subsystems a decision-maker would
   recognize ("Authentication & authorization", "Document editing pipeline") — not
   one doc per directory. Every non-deferred doc gets 3–8 `entryPoints`: repo-relative
   paths where a fresh explorer should start.

3. **Create the ProductNow folder structure** (skip entirely if DRY RUN):
   - Call `list_folders`, then `create_folder` for a top-level folder named
     `RTFM: <repo name>`.
   - Create subfolders only if the corpus naturally groups (e.g. Backend / Frontend /
     Infrastructure); otherwise keep every doc in the top folder.
   - Record real folder ids in the plan file.

4. **Write the plan file** with the Write tool to the absolute path given as
   `PLAN_PATH` in the Runtime parameters section below.

## Plan file schema (produce exactly this shape)

```json
{
  "repo": "<repo name>",
  "generatedAt": "<ISO 8601 date>",
  "rootFolderId": "<ProductNow folder id, or DRY-RUN>",
  "docs": [
    {
      "slug": "unique-kebab-case",
      "title": "Human-readable title",
      "deferred": false,
      "folderId": "<ProductNow folder id, or DRY-RUN>",
      "scope": "One sentence: what this doc covers and what questions it answers.",
      "entryPoints": ["packages/backend/src/security", "packages/backend/src/mcp"],
      "relatedSlugs": ["sibling-doc-slug"]
    }
  ]
}
```

## Rules

- Slugs are unique. Exactly ONE doc has `"deferred": true` (the overview); it needs
  no `entryPoints`.
- `relatedSlugs` must reference slugs that exist in this plan.
- If a `DRY RUN: yes` runtime parameter is present, do not call any MCP tools and
  use the string `DRY-RUN` for every folder id.
- Your final message must be exactly: `PLAN WRITTEN <n> docs` (n = total including
  the deferred overview).
