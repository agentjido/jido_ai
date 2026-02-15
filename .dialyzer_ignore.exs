[
  # Upstream Jido typing warnings (dependency code outside this repo).
  ~r/deps\/jido\/lib\/jido\/agent\.ex.*pattern_match/,

  # TermUI currently triggers opaque/no_return analysis noise in the renderer.
  ~r/lib\/jido_ai\/cli\/tui\.ex/,

  # False positive: dialyzer reports an impossible boolean match at module line 1.
  ~r/lib\/jido_ai\/executor\.ex:1:pattern_match/,

  # Same module-level false positive in unified CLI mix task.
  ~r/lib\/mix\/tasks\/jido_ai\.ex:1:pattern_match/
]
