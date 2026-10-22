# Agent Skills conformance fixtures

These fixtures follow the Agent Skills specification and the public
`skills-ref` validator cases reviewed on 2026-08-26.

Jido.AI makes these documented compatibility choices:

- Filesystem loading requires the exact filename `SKILL.md`, as required by the
  specification. The reference parser also accepts lowercase `skill.md`.
- Skill names use the ASCII `a-z`, `0-9`, and hyphen grammar stated in the
  specification table. The reference validator also accepts lowercase Unicode
  letters and numbers.
- Strict runtime loading rejects unknown top-level fields. Lenient parsing keeps
  them only for diagnostics and migration.
- An optional UTF-8 BOM is accepted for interoperability.

