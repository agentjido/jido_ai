# Phase 5: Self-Correcting RAG (Reference)

This phase references the existing Self-Correcting RAG implementation plan in the jido_code project. Rather than duplicating the detailed planning documents, this document explains how Phase 5 fits into the accuracy stack and defines the integration points between the general accuracy components in jido_ai and the domain-specific RAG implementation in jido_code.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Accuracy Stack - Phase 5: RAG                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   jido_ai (General Accuracy Layer)                                     │
│   ┌──────────────────────────────────────────────────────────────┐    │
│   │  AccuracyPipeline                                            │    │
│   │    │                                                         │    │
│   │    ├──→ RAG Strategy Selector                                │    │
│   │    │                                                         │    │
│   │    └──→ RAGPolicy (orchestrates RAG with correction)         │    │
│   └───────────────────────────┬──────────────────────────────────┘    │
│                               │                                        │
│                               │ implements                             │
│                               │ Retriever behaviour                    │
│                               ▼                                        │
│   jido_code (Domain-Specific RAG Layer)                               │
│   ┌──────────────────────────────────────────────────────────────┐    │
│   │  Corrective RAG Plan                                          │    │
│   │    │                                                         │    │
│   │    ├──→ Retriever behaviour (interface)                      │    │
│   │    ├──→ RetrievalEvaluation (quality assessment)             │    │
│   │    ├──→ CorrectiveRAG (core algorithm)                       │    │
│   │    ├──→ Corrective actions (re-query, expand, switch)        │    │
│   │    └──→ KnowledgeGraph.Retriever (Elixir code knowledge)     │    │
│   └──────────────────────────────────────────────────────────────┘    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Phase Location

**Self-Correcting RAG planning documents are located in:**
```
/home/ducky/code/agentjido/jido_code/notes/planning/corrective/
├── overview.md
├── phase-01-interface.md
├── phase-02-algorithm.md
└── (additional phases as defined in corrective plan)
```

## Why This Separation?

| Aspect | jido_ai (Accuracy) | jido_code (Corrective RAG) |
|--------|-------------------|---------------------------|
| **Scope** | General-purpose accuracy improvements | Elixir-code-specific retrieval |
| **Dependencies** | LLM providers, verifiers, search | Elixir code ontology, SPARQL |
| **Reusability** | Can be used with any RAG system | Specialized for Elixir code |
| **Layer** | AI/LLM orchestration layer | Domain knowledge layer |

---

## Corrective RAG Plan Contents

### Phase 1: RAG Interface & Evaluation
**File:** `jido_code/notes/planning/corrective/phase-01-interface.md`

Components defined:
- `JidoCode.RAG.Retriever` behaviour
- `JidoCode.RAG.RetrievalEvaluation` struct
- `JidoCode.RAG.Result` struct
- `JidoCode.RAG.Actions` (action types)
- `JidoCode.RAG.Telemetry` events

### Phase 2: Corrective RAG Algorithm
**File:** `jido_code/notes/planning/corrective/phase-02-algorithm.md`

Components defined:
- `JidoCode.RAG.CorrectiveRAG` (core algorithm)
- `JidoCode.RAG.Machine` (state machine)
- `JidoCode.RAG.Prompts` (templates)
- Corrective action implementations:
  - `ReQuery`
  - `ExpandContext`
  - `SwitchCorpus`
  - `Abstain`

### Additional Phases
See `jido_code/notes/planning/corrective/overview.md` for complete phase list.

---

## Integration Points

### 5.1 RAG Policy Module

Create the jido_ai module that orchestrates RAG with self-correction.

- [ ] 5.1.1 Create `lib/jido_ai/accuracy/strategies/rag_policy.ex`
- [ ] 5.1.2 Add `@moduledoc` explaining RAG policy pattern
- [ ] 5.1.3 Define configuration schema:
  - `:retriever` - Retriever module (implements jido_code behaviour)
  - `:max_attempts` - Maximum correction attempts
  - `:selective_rag` - Whether to use selective RAG
  - `:correction_threshold` - Threshold for triggering correction
- [ ] 5.1.4 Implement `run/3` with strategy selection
- [ ] 5.1.5 Implement `should_use_rag?/2` for selective RAG
- [ ] 5.1.6 Implement `run_with_correction/3`
- [ ] 5.1.7 Implement `run_without_rag/2`

### 5.2 Accuracy Stack Integration

Define how RAG fits into the overall accuracy pipeline.

- [ ] 5.2.1 Create `lib/jido_ai/accuracy/rag_integration.ex`
- [ ] 5.2.2 Add `@moduledoc` explaining integration approach
- [ ] 5.2.3 Implement `rag_precheck/2` - decides if RAG is needed
- [ ] 5.2.4 Implement `wrap_with_rag/3` - wraps generation with RAG
- [ ] 5.2.5 Implement `merge_rag_context/2` - combines retrieved context
- [ ] 5.2.6 Implement `rag_quality_gate/3` - checks retrieval quality

### 5.3 RAG Strategy Adapter

Create adapter for using jido_code retrievers with jido_ai accuracy components.

- [ ] 5.3.1 Create `lib/jido_ai/accuracy/adapters/retriever_adapter.ex`
- [ ] 5.3.2 Add `@moduledoc` explaining adapter pattern
- [ ] 5.3.3 Implement `to_jido_ai_result/1` - converts jido_code results
- [ ] 5.3.4 Implement `from_jido_ai_query/1` - converts queries
- [ ] 5.3.5 Implement `wrap_retriever/1` - wraps jido_code retriever

### 5.4 CRAG Strategy Wrapper

Create a strategy that implements CRAG using jido_code components.

- [ ] 5.4.1 Create `lib/jido_ai/accuracy/strategies/crag.ex`
- [ ] 5.4.2 Add `@moduledoc` explaining CRAG strategy
- [ ] 5.4.3 Define configuration schema:
  - `:retriever` - jido_code retriever module
  - `:evaluator` - Retrieval evaluation module
  - `:max_corrections` - Maximum correction attempts
- [ ] 5.4.4 Implement `run/3` using jido_code CorrectiveRAG
- [ ] 5.4.5 Implement `handle_retrieval/3`
- [ ] 5.4.6 Implement `handle_correction/3`
- [ ] 5.4.7 Implement `generate_with_context/3`

---

## Files from Corrective RAG Plan

### Core Files to Reference

| File | Location | Purpose |
|------|----------|---------|
| Retriever behaviour | `lib/jido_ai/rag/retriever.ex` | Interface for knowledge sources |
| RetrievalEvaluation | `lib/jido_ai/rag/evaluation.ex` | Quality assessment results |
| Result | `lib/jido_ai/rag/result.ex` | Retrieval results struct |
| CorrectiveRAG | `lib/jido_ai/rag/corrective_rag.ex` | Core algorithm |
| Actions | `lib/jido_ai/rag/corrective_actions.ex` | Action dispatcher |
| Machine | `lib/jido_ai/rag/machine.ex` | State machine |

Note: These files are created in **jido_ai** (not jido_code) because the RAG interface is general-purpose. The domain-specific implementation (KnowledgeGraph.Retriever) lives in jido_code.

---

## Phase 5 Unit Tests

### 5.5.1 RAG Policy Tests

- [ ] Test `run/3` selects appropriate strategy
- [ ] Test `should_use_rag?/2` decision logic
- [ ] Test `run_with_correction/3` handles correction loop
- [ ] Test `run_without_rag/2` falls back correctly

### 5.5.2 Integration Tests

- [ ] Test RAG precheck identifies need for retrieval
- [ ] Test RAG context merge combines correctly
- [ ] Test quality gate rejects poor retrieval
- [ ] Test adapter converts between formats

### 5.5.3 CRAG Strategy Tests

- [ ] Test CRAG wraps jido_code retriever correctly
- [ ] Test correction loop executes properly
- [ ] Test max corrections enforced

---

## Phase 5 Integration Tests

### 5.6.1 End-to-End RAG Tests

- [ ] 5.6.1.1 Create `test/jido_ai/accuracy/rag_integration_test.exs`
- [ ] 5.6.1.2 Test: RAG with correction outperforms baseline
  - Compare standard RAG vs self-correcting RAG
  - Measure accuracy improvement
- [ ] 5.6.1.3 Test: Factuality improved with correction
  - Measure hallucination rate
  - Verify reduction with self-correcting RAG
- [ ] 5.6.1.4 Test: Selective RAG works correctly
  - Query requiring external knowledge
  - Query answerable without RAG
  - Verify correct decisions

### 5.6.2 Cross-Project Integration Tests

- [ ] 5.6.2.1 Test: jido_ai pipeline calls jido_code retriever
  - Configure jido_ai with jido_code retriever
  - Verify successful cross-project call
- [ ] 5.6.2.2 Test: Evaluation results flow correctly
  - Generate retrieval evaluation in jido_code
  - Verify jido_ai receives and uses results
- [ ] 5.6.2.3 Test: Correction actions execute
  - Trigger re-query from jido_ai
  - Verify jido_code executes correction

---

## Phase 5 Success Criteria

1. **RAG interface**: jido_ai can use jido_code retrievers through behaviour
2. **Evaluation flow**: Retrieval evaluation results used for correction decisions
3. **Correction loop**: jido_ai orchestrates correction using jido_code components
4. **Integration**: Cross-project calls work seamlessly
5. **Accuracy improvement**: RAG with correction outperforms baseline

---

## Phase 5 Critical Files

**In jido_ai (created by this plan):**
- `lib/jido_ai/accuracy/strategies/rag_policy.ex`
- `lib/jido_ai/accuracy/rag_integration.ex`
- `lib/jido_ai/accuracy/adapters/retriever_adapter.ex`
- `lib/jido_ai/accuracy/strategies/crag.ex`

**In jido_code (referenced from corrective plan):**
- `lib/jido_ai/rag/retriever.ex`
- `lib/jido_ai/rag/evaluation.ex`
- `lib/jido_ai/rag/result.ex`
- `lib/jido_ai/rag/corrective_rag.ex`
- `lib/jido_ai/rag/corrective_actions.ex`
- `lib/jido_ai/rag/machine.ex`
- `lib/jido_code/knowledge_graph/retriever.ex` (domain implementation)

**Test Files:**
- `test/jido_ai/accuracy/strategies/rag_policy_test.exs`
- `test/jido_ai/accuracy/rag_integration_test.exs`
- `test/jido_ai/accuracy/adapters/retriever_adapter_test.exs`
- `test/jido_ai/accuracy/strategies/crag_test.exs`

---

## References

- **Corrective RAG Overview:** `jido_code/notes/planning/corrective/overview.md`
- **Phase 1 (Interface):** `jido_code/notes/planning/corrective/phase-01-interface.md`
- **Phase 2 (Algorithm):** `jido_code/notes/planning/corrective/phase-02-algorithm.md`
- **Accuracy Stack Overview:** `jido_ai/notes/planning/accuracy/overview.md`
