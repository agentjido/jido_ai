[
  %{
    pattern: ~r/deps\/jido\/lib\/jido\/agent\.ex.*pattern_match/,
    owner: "jido-ai-maintainers",
    rationale: "Upstream jido type specs currently emit false-positive pattern match warnings.",
    cleanup_plan: "Remove after upgrading to a jido release that fixes the related specs.",
    reviewed_by: "mhostetler",
    reviewed_on: "2026-02-16"
  },
  %{
    pattern: ~r/lib\/jido_ai\/cli\/tui\.ex/,
    owner: "jido-ai-maintainers",
    rationale: "TermUI integration currently produces opaque/no_return analysis noise in dialyzer.",
    cleanup_plan: "Replace with concrete types after term_ui publishes stronger specs.",
    reviewed_by: "mhostetler",
    reviewed_on: "2026-02-16"
  },
  %{
    pattern: ~r/lib\/jido_ai\/executor\.ex:1:pattern_match/,
    owner: "jido-ai-maintainers",
    rationale: "Dialyzer reports a module-level false-positive boolean pattern match.",
    cleanup_plan: "Drop ignore once the surrounding control flow is retyped in issue #127.",
    reviewed_by: "mhostetler",
    reviewed_on: "2026-02-16"
  },
  %{
    pattern: ~r/lib\/mix\/tasks\/jido_ai\.ex:1:pattern_match/,
    owner: "jido-ai-maintainers",
    rationale: "False-positive pattern match warning mirrors the unified CLI task entrypoint.",
    cleanup_plan: "Re-evaluate after CLI task type contracts are tightened in issue #127.",
    reviewed_by: "mhostetler",
    reviewed_on: "2026-02-16"
  }
]
