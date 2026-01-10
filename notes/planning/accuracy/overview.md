# Accuracy Improvement Implementation Plan

## Overview

This plan implements test-time compute scaling algorithms for improved LLM accuracy in Jido.AI, based on the research in `notes/research/improving-accuracy.md`.

The practical "accuracy stack" improves LLM responses through intelligent use of additional compute time:

```
1. RAG (selective) → 2. Generate multiple candidates → 3. Verify/rank (PRM)
   → 4. If fails: critique+revise → 5. Calibration gate (abstain/escalate)
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Complete Accuracy Stack                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Query                                                                  │
│     │                                                                    │
│     ▼                                                                    │
│   ┌──────────────────┐                                                  │
│   │ Difficulty       │ ──→ Easy: N=3, no PRM                           │
│   │ Estimation       │ ──→ Medium: N=5, PRM                             │
│   └────────┬─────────┘ ──→ Hard: N=10, PRM + search                     │
│            │                                                              │
│            ▼                                                              │
│   ┌──────────────────┐                                                   │
│   │ RAG with         │ ──→ See phase-05-crag-reference.md               │
│   │ Correction       │                                                     │
│   └────────┬─────────┘                                                     │
│            │                                                              │
│            ▼                                                              │
│   ┌──────────────────┐                                                   │
│   │ Multi-Candidate  │ ──→ See phase-01-self-consistency.md             │
│   │ Generation       │                                                     │
│   └────────┬─────────┘                                                     │
│            │                                                              │
│            ▼                                                              │
│   ┌──────────────────┐                                                   │
│   │ Verification     │ ──→ See phase-02-verifier.md                      │
│   │ (Outcome/PRM)    │                                                     │
│   └────────┬─────────┘                                                     │
│            │                                                              │
│            ▼                                                              │
│   ┌──────────────────┐                                                   │
│   │ Search /         │ ──→ See phase-03-search.md                        │
│   │ Selection        │                                                     │
│   └────────┬─────────┘                                                     │
│            │                                                              │
│            ▼                                                              │
│   ┌──────────────────┐                                                   │
│   │ Reflection       │ ──→ See phase-04-reflection.md                    │
│   │ (if needed)      │                                                     │
│   └────────┬─────────┘                                                     │
│            │                                                              │
│            ▼                                                              │
│   ┌──────────────────┐                                                   │
│   │ Calibration      │ ──→ See phase-06-calibration.md                   │
│   │ Gate             │                                                     │
│   └────────┬─────────┘                                                     │
│            │                                                              │
│            ▼                                                              │
│        Response                                                            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Phase Summary

| Phase | Document | Focus | Key Components |
|-------|----------|-------|----------------|
| 1 | phase-01-self-consistency.md | Self-Consistency & Best-of-N | Candidate generation, voting, aggregation |
| 2 | phase-02-verifier.md | Verifier System | Outcome verifiers, Process Reward Models |
| 3 | phase-03-search.md | Search Controllers | Beam search, MCTS, diverse decoding |
| 4 | phase-04-reflection.md | Reflection Loops | Self-critique, iterative refinement |
| 5 | phase-05-crag-reference.md | Self-Correcting RAG | References corrective RAG plan in jido_code |
| 6 | phase-06-calibration.md | Uncertainty & Calibration | Confidence estimation, selective generation |
| 7 | phase-07-adaptive.md | Adaptive Budgeting | Difficulty estimation, compute routing |
| 8 | phase-08-integration.md | Complete Stack Integration | End-to-end accuracy pipeline |

## Phase Documents

- [Phase 1: Self-Consistency and Best-of-N Sampling](phase-01-self-consistency.md)
- [Phase 2: Verifier System](phase-02-verifier.md)
- [Phase 3: Search Controllers](phase-03-search.md)
- [Phase 4: Reflection and Self-Critique Loops](phase-04-reflection.md)
- [Phase 5: Self-Correcting RAG (Reference)](phase-05-crag-reference.md)
- [Phase 6: Uncertainty Estimation and Calibration Gates](phase-06-calibration.md)
- [Phase 7: Adaptive Compute Budgeting](phase-07-adaptive.md)
- [Phase 8: Complete Accuracy Stack Integration](phase-08-integration.md)

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Candidate generation | Parallel LLM sampling | Faster than sequential, enables diversity |
| Aggregation strategy | Majority vote + best-of-N | Combines robustness with quality |
| Verification | LLM + deterministic + tool-based | Multiple verification methods for different domains |
| Search algorithm | Beam search + MCTS | Beam for breadth, MCTS for deep exploration |
| Reflection | Generate-critique-revise loop | Proven pattern for iterative improvement |
| RAG approach | Separate plan in jido_code | Domain-specific retrieval vs general accuracy |
| Calibration | Confidence-based routing | Prevents wrong answers through selective generation |
| Budget allocation | Difficulty-based | Efficient use of compute resources |

## Success Criteria

1. **Self-Consistency**: Generate and aggregate multiple candidate responses
2. **Verification**: Score candidates with outcome and process verifiers
3. **Search**: Beam search and MCTS for better candidate selection
4. **Reflection**: Iteratively improve responses through self-critique
5. **Self-Correcting RAG**: Evaluate and correct retrieval quality (via jido_code plan)
6. **Calibration**: Confidence-based routing and selective answering
7. **Adaptive Compute**: Difficulty-based resource allocation
8. **Complete Pipeline**: End-to-end accuracy improvement system
9. **Test Coverage**: Minimum 80% across all accuracy modules

## References

Based on research in `notes/research/improving-accuracy.md`:

- Scaling LLM Test-Time Compute Optimally (arXiv:2408.03314)
- Revisiting Test-Time Scaling of o1-like Models (ACL 2025)
- R-PRM: Reasoning-Driven Process Reward Modeling (EMNLP 2025)
- Self-Consistency Improves Chain of Thought Reasoning (arXiv:2203.11171)
- Reflexion: Language Agents with Verbal Reinforcement (arXiv:2303.11366)
- Self-Refine: Iterative Refinement with Self-Feedback (arXiv:2303.17651)
- Self-RAG: Learning to Retrieve, Generate, and Critique (arXiv:2310.11511)
- Corrective RAG (arXiv:2401.15884)
- Confidence Estimation and Calibration Survey (NAACL 2024)
