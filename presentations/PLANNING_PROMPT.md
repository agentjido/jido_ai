# Jido Presentation Planning Prompt

Use this prompt to investigate the source code of a Jido project and produce a comprehensive presentation outline grounded in the real code.

Fill in the variables and follow the steps precisely.

- Topic: {{topic_name}}
- Project path: {{project_path}} (absolute in the workspace)
- Audience: Engineers familiar with Elixir, new to Jido
- Duration: 10–20 minutes (target 14–18 slides)
- Learning goals (draft): {{learning_goals}}

## Objectives
1) Build a clear conceptual model of the component (purpose, lifecycle, data flow).
2) Extract the real API (public modules, functions, types, options) from lib/ and README.
3) Select realistic examples from tests and guides.
4) Produce a slide-by-slide outline suitable for Slidev with code snippets and speaker notes.

## Sources to Analyze (in order)
1. README.md for quickstart and intent.
2. guides/**/*.md for deeper narrative.
3. mix.exs (app name, deps, aliases), usage-rules.md if present.
4. lib/**/*.ex focusing on public modules and boundary structs.
5. test/**/*.exs to find runnable, end-to-end usage examples.

## What to Extract
- Design goals and key concepts (definitions, when to use, constraints).
- Core modules and primary public functions (signatures, inputs/outputs, options, return types).
- Data flow and lifecycle (state transitions, events) – consider a Mermaid diagram outline.
- Error handling behaviors and common pitfalls.
- Minimal end-to-end example (from tests or guides) showing setup → execution → assertion.
- Integration points with the rest of Jido (signals ↔ actions ↔ agents ↔ workflows ↔ AI).

## Slide Plan (customize per topic)
Aim for 14–18 slides, roughly 1 concept/slide, ~1 minute each:
1. Cover: Title, subtitle, who this is for
2. Learning objectives
3. Why this exists (problem/constraints)
4. Mental model diagram (high level)
5–8. API walkthrough (2–4 slides): key modules, functions, and structs
9–11. Code tour (end-to-end example from tests), with highlights
12. Error handling & debugging tips
13. Performance or scaling considerations (if applicable)
14. Integration with other Jido components
15. Pitfalls & best practices
16. Mini-quiz or recap
17. Further reading & links
18. Next steps / hands-on exercise

## Output Format (strict)
Produce a single Markdown document. For each slide, use this exact structure:

### Slide {{n}}: {{title}}

Content:
- Bullet 1
- Bullet 2

Code:
```elixir
# If including code, keep it ≤ 20 lines.
# Prefer real snippets from the repository; include a comment indicating source path.
# e.g., # source: lib/jido_signal/signal.ex
```

Notes:
- Speaker notes for the facilitator. Keep crisp, 1–4 bullets.

Repeat for all slides.

Rules:
- Prefer real code. Do not invent APIs.
- If code is long, include the most relevant excerpt and summarize the rest.
- Use accurate module and function names; include options and return types where relevant.
- Use consistent naming and tone.
- Keep slides self-contained; avoid cross references that require flipping back.

## Deliverable
A complete outline saved to presentations/topics/{{topic_file}}.md that Slidev authors can convert into slides with minimal rewriting. Include enough detail in Notes to guide a live presenter.
