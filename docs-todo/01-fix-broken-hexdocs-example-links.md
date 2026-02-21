# Issue 01: Fix Broken HexDocs Example Links

## Severity

- P1

## Problem

Several links in published HexDocs currently point to local repository paths that are not available in the generated docs site.

## Impact

- Readers hit broken links from the main entry points.
- Trust and usability drop during first evaluation.

## Evidence

- `/Users/mhostetler/Source/Jido/jido_ai/README.md:124`
- `/Users/mhostetler/Source/Jido/jido_ai/README.md:125`
- `/Users/mhostetler/Source/Jido/jido_ai/README.md:126`
- `/Users/mhostetler/Source/Jido/jido_ai/README.md:127`
- `/Users/mhostetler/Source/Jido/jido_ai/README.md:128`
- `/Users/mhostetler/Source/Jido/jido_ai/README.md:133`
- `/Users/mhostetler/Source/Jido/jido_ai/guides/developer/actions_catalog.md:41`
- `/Users/mhostetler/Source/Jido/jido_ai/guides/developer/actions_catalog.md:56`

## Recommended Fix

- Replace local file links with one of:
  - GitHub source links pinned to `main` or release tags.
  - Inline runnable snippets in guides.
  - Links to module docs when example behavior is already covered in API docs.
- Re-run `mix docs` and validate all internal links.

## Acceptance Criteria

- No broken links from `doc/readme.html` and `doc/actions_catalog.html`.
- Link checker reports zero broken internal links.
