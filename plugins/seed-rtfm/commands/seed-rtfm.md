---
description: Seed a first-pass RTFM documentation corpus into ProductNow for this repository
argument-hint: "[--dry-run] [--parallel N] [--review] [--force] [--audience TEXT]"
---

Run the bundled seed-rtfm script against the current repository using the Bash tool. Run it from the repository root (the directory this session is working in) exactly as follows, passing through any arguments given:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/seed-rtfm.sh" $ARGUMENTS
```

Stream the script's own progress output back to the user as each phase (PLAN, WORKERS, OVERVIEW, REGISTRY, VERIFY) runs — do not wait silently for it to finish. When it completes, report which docs were published (with their URLs, from the final "All N docs published" listing) and call out any docs the VERIFY phase reported as missing, since those can be retried by running `/seed-rtfm` again.
