# Feature Planning: Accuracy Strategy Presets (Phase 8.2)

## Status

**Status**: Complete
**Created**: 2025-01-15
**Completed**: 2025-01-15
**Branch**: `feature/accuracy-phase-8-2-presets`

---

## Problem Statement

The accuracy pipeline (Phase 8.1) is fully implemented with configurable stages and options. However, users need to manually configure all settings for different use cases. This creates friction and makes it difficult to get optimal results without deep understanding of the system.

**Impact**:
- Users must understand all pipeline options to use effectively
- No "sensible defaults" for common scenarios
- Difficult to balance cost vs. accuracy trade-offs
- No optimization for specific domains (coding, research, etc.)

---

## Solution Overview

Implement **Strategy Presets** - pre-configured pipeline configurations optimized for common use cases. Users can select a preset by name and optionally customize specific settings.

**Key Design Decisions**:
1. Presets return `PipelineConfig` structs for direct pipeline use
2. Each preset targets a specific use case with optimized trade-offs
3. Presets are composable - can be customized after selection
4. Preset validation ensures configuration integrity

---

## Agent Consultations Performed

### Research: Existing PipelineConfig Structure
**Consulted**: Direct code inspection
**Findings**:
- `PipelineConfig` struct with stages and per-stage configs
- `generation_config`: min_candidates, max_candidates, batch_size, early_stop_threshold
- `verifier_config`: use_outcome, use_process, verifiers, parallel
- `search_config`: enabled, algorithm, beam_width, iterations
- `reflection_config`: enabled, max_iterations, convergence_threshold
- `calibration_config`: high_threshold, low_threshold, medium_action, low_action
- `rag_config`: enabled, retriever, correction

---

## Technical Details

### File Structure

```
lib/jido_ai/accuracy/
├── presets.ex                    # NEW - Main presets module
└── presets/                      # NEW - Preset definitions
    ├── fast.ex                   # Fast preset
    ├── balanced.ex               # Balanced preset
    ├── accurate.ex               # Accurate preset
    ├── coding.ex                 # Coding preset
    └── research.ex               # Research preset

test/jido_ai/accuracy/
├── presets_test.exs              # NEW - Main presets tests
└── presets/                      # NEW - Preset-specific tests
    ├── fast_test.exs
    ├── balanced_test.exs
    ├── accurate_test.exs
    ├── coding_test.exs
    └── research_test.exs
```

### Dependencies

- **Required**: `Jido.AI.Accuracy.PipelineConfig` (already implemented)
- **Required**: `Jido.AI.Accuracy.Thresholds` (already implemented)
- **Optional**: Verifier modules for specific presets

### Configuration Mapping

| Preset Attribute | PipelineConfig Field |
|-----------------|---------------------|
| num_candidates | generation_config.max_candidates (min adjusted) |
| use_prm | verifier_config.use_process |
| use_search | stages includes :search |
| use_reflection | stages includes :reflection |
| use_rag | stages includes :rag (or :selective_rag) |
| calibration: strict | calibration_config thresholds adjusted |
| verifiers | verifier_config.verifiers list |
| search_iterations | search_config.iterations |

---

## Success Criteria

1. ✅ All 5 presets defined and accessible
2. ✅ `Presets.get/1` returns valid PipelineConfig for each preset name
3. ✅ `Presets.list/0` returns all available preset names
4. ✅ `Presets.customize/2` allows preset modification
5. ✅ `Presets.validate/1` validates preset configurations
6. ✅ All tests pass (minimum 95% coverage)
7. ✅ Presets work with existing Pipeline.run/3

---

## Implementation Plan

### Step 1: Create Presets Module (8.2.1)

**File**: `lib/jido_ai/accuracy/presets.ex`

**Tasks**:
- [ ] 1.1 Create module with @moduledoc explaining preset concept
- [ ] 1.2 Define @type preset() :: :fast | :balanced | :accurate | :coding | :research
- [ ] 1.3 Implement `get/1` for preset retrieval
- [ ] 1.4 Implement `list/0` returning all preset names
- [ ] 1.5 Implement `customize/2` for preset modification
- [ ] 1.6 Implement `validate/1` for preset validation
- [ ] 1.7 Implement `to_pipeline_config/1` helper

**Code Structure**:
```elixir
defmodule Jido.AI.Accuracy.Presets do
  @type preset :: :fast | :balanced | :accurate | :coding | :research

  @spec get(preset()) :: {:ok, PipelineConfig.t()} | {:error, term()}
  @spec list() :: [preset()]
  @spec customize(preset(), map()) :: {:ok, PipelineConfig.t()} | {:error, term()}
  @spec validate(preset()) :: :ok | {:error, term()}
end
```

---

### Step 2: Implement Preset Definitions (8.2.2)

#### 2.1 Fast Preset

**Target**: Minimal compute, basic verification
**Configuration**:
```elixir
%{
  stages: [:generation, :calibration],
  generation_config: %{
    min_candidates: 1,
    max_candidates: 3,
    batch_size: 3,
    early_stop_threshold: 0.9
  },
  verifier_config: %{
    use_outcome: true,
    use_process: false,
    verifiers: []
  },
  calibration_config: %{
    high_threshold: 0.8,  # More lenient
    low_threshold: 0.5,
    medium_action: :direct,
    low_action: :abstain
  }
}
```

#### 2.2 Balanced Preset

**Target**: Moderate compute, full verification
**Configuration**:
```elixir
%{
  stages: [:difficulty_estimation, :generation, :verification, :calibration],
  generation_config: %{
    min_candidates: 3,
    max_candidates: 5,
    batch_size: 3,
    early_stop_threshold: 0.8
  },
  verifier_config: %{
    use_outcome: true,
    use_process: true,
    verifiers: []
  },
  calibration_config: %{
    high_threshold: 0.7,
    low_threshold: 0.4,
    medium_action: :with_verification,
    low_action: :abstain
  }
}
```

#### 2.3 Accurate Preset

**Target**: Maximum compute, all features
**Configuration**:
```elixir
%{
  stages: [:difficulty_estimation, :generation, :verification, :search, :reflection, :calibration],
  generation_config: %{
    min_candidates: 5,
    max_candidates: 10,
    batch_size: 3,
    early_stop_threshold: 0.7
  },
  verifier_config: %{
    use_outcome: true,
    use_process: true,
    verifiers: []
  },
  search_config: %{
    enabled: true,
    algorithm: :beam_search,
    beam_width: 5,
    iterations: 50
  },
  reflection_config: %{
    enabled: true,
    max_iterations: 3,
    convergence_threshold: 0.1
  },
  calibration_config: %{
    high_threshold: 0.8,  # Stricter
    low_threshold: 0.3,
    medium_action: :with_verification,
    low_action: :abstain
  }
}
```

#### 2.4 Coding Preset

**Target**: Optimized for code correctness
**Configuration**:
```elixir
%{
  stages: [:difficulty_estimation, :rag, :generation, :verification, :reflection, :calibration],
  generation_config: %{
    min_candidates: 3,
    max_candidates: 5,
    batch_size: 3,
    early_stop_threshold: 0.8
  },
  rag_config: %{
    enabled: true,
    correction: true
  },
  verifier_config: %{
    use_outcome: true,
    use_process: true,
    verifiers: [:code_syntax, :code_execution]
  },
  reflection_config: %{
    enabled: true,
    max_iterations: 2,
    convergence_threshold: 0.15
  },
  calibration_config: %{
    high_threshold: 0.75,
    low_threshold: 0.4,
    medium_action: :with_verification,
    low_action: :abstain
  }
}
```

#### 2.5 Research Preset

**Target**: Optimized for factual QA
**Configuration**:
```elixir
%{
  stages: [:difficulty_estimation, :rag, :generation, :verification, :calibration],
  generation_config: %{
    min_candidates: 3,
    max_candidates: 5,
    batch_size: 3,
    early_stop_threshold: 0.8
  },
  rag_config: %{
    enabled: true,
    correction: true
  },
  verifier_config: %{
    use_outcome: true,
    use_process: true,  # PRM for factual verification
    verifiers: [:factuality]
  },
  calibration_config: %{
    high_threshold: 0.85,  # Very strict for facts
    low_threshold: 0.5,
    medium_action: :with_citations,
    low_action: :abstain
  }
}
```

---

### Step 3: Implement Preset Operations (8.2.3)

**File**: `lib/jido_ai/accuracy/presets.ex`

#### 3.1 get/1 - Preset Retrieval
```elixir
@spec get(preset()) :: {:ok, PipelineConfig.t()} | {:error, term()}
def get(:fast), do: {:ok, FastPreset.config()}
def get(:balanced), do: {:ok, BalancedPreset.config()}
def get(:accurate), do: {:ok, AccuratePreset.config()}
def get(:coding), do: {:ok, CodingPreset.config()}
def get(:research), do: {:ok, ResearchPreset.config()}
def get(_), do: {:error, :unknown_preset}
```

#### 3.2 list/0 - Available Presets
```elixir
@spec list() :: [preset()]
def list, do: [:fast, :balanced, :accurate, :coding, :research]
```

#### 3.3 customize/2 - Preset Modification
```elixir
@spec customize(preset(), map()) :: {:ok, PipelineConfig.t()} | {:error, term()}
def customize(preset, overrides) when is_map(overrides) do
  with {:ok, config} <- get(preset),
       {:ok, merged} <- PipelineConfig.merge(config, overrides) do
    {:ok, merged}
  end
end
```

#### 3.4 validate/1 - Preset Validation
```elixir
@spec validate(preset()) :: :ok | {:error, term()}
def validate(preset) do
  case get(preset) do
    {:ok, config} -> PipelineConfig.validate(config)
    error -> error
  end
end
```

---

### Step 4: Unit Tests (8.2.4)

**File**: `test/jido_ai/accuracy/presets_test.exs`

**Test Cases**:
- [ ] 4.1 Test `get/1` returns valid config for each preset
- [ ] 4.2 Test `get/1` returns error for unknown preset
- [ ] 4.3 Test `list/0` returns all 5 preset names
- [ ] 4.4 Test `customize/2` modifies preset correctly
- [ ] 4.5 Test `customize/2` validates overrides
- [ ] 4.6 Test `validate/1` passes for all presets
- [ ] 4.7 Test each preset has correct stages
- [ ] 4.8 Test each preset has correct candidate counts
- [ ] 4.9 Test fast preset has minimal stages
- [ ] 4.10 Test accurate preset has all stages
- [ ] 4.11 Test coding preset includes RAG and code verifiers
- [ ] 4.12 Test research preset includes RAG and factuality verifier
- [ ] 4.13 Test presets work with Pipeline.run/3

---

## Current Status

### What Works
- Research completed on PipelineConfig structure
- Feature branch created
- Planning document created

### What's Next
- Implement Presets module with all preset definitions
- Write comprehensive unit tests
- Update planning document as implementation progresses

### How to Run Tests
```bash
# Test presets module
MIX_ENV=test mix test test/jido_ai/accuracy/presets_test.exs

# Test with pipeline
MIX_ENV=test mix test test/jido_ai/accuracy/presets_test.exs test/jido_ai/accuracy/pipeline_test.exs
```

---

## Notes and Considerations

### Design Decisions
1. **Single File vs. Multiple Files**: Using a single `presets.ex` file with internal preset configurations rather than separate files. This keeps the API surface smaller and makes it easier to see all presets at once.

2. **Preset Storage**: Presets are defined as module attributes that return configuration maps. This is simpler than using separate GenServer or ETS storage.

3. **Customization Approach**: Using `PipelineConfig.merge/2` which already exists. This ensures consistency with existing API.

4. **Validation**: Leveraging existing `PipelineConfig.validate/1` rather than duplicating validation logic.

### Potential Issues
1. **Verifier Module Availability**: Coding and research presets reference verifier modules that may not exist yet (`:code_syntax`, `:code_execution`, `:factuality`). These should be optional/handled gracefully.

2. **RAG Module**: The RAG stage reference in presets assumes the RAG stage is fully functional. Need to verify RAG stage availability.

3. **Backward Compatibility**: New presets module doesn't affect existing code, so no breaking changes.

### Future Enhancements
1. **User-defined presets**: Allow users to save and name custom configurations
2. **Preset comparison**: Utility to compare two presets and show differences
3. **Preset recommendations**: Suggest preset based on query characteristics
4. **Cost estimation**: Display estimated token/cost for each preset
5. **A/B testing**: Compare multiple presets on same query

---

## Implementation Checklist

- [ ] Step 1: Create Presets module (8.2.1)
  - [ ] 1.1 Create `lib/jido_ai/accuracy/presets.ex`
  - [ ] 1.2 Define @type preset()
  - [ ] 1.3 Implement get/1
  - [ ] 1.4 Implement list/0
  - [ ] 1.5 Implement customize/2
  - [ ] 1.6 Implement validate/1

- [ ] Step 2: Implement preset definitions (8.2.2)
  - [ ] 2.1 fast/0 preset
  - [ ] 2.2 balanced/0 preset
  - [ ] 2.3 accurate/0 preset
  - [ ] 2.4 coding/0 preset
  - [ ] 2.5 research/0 preset

- [ ] Step 3: Implement preset operations (8.2.3)
  - [ ] 3.1 Ensure get/1 works for all presets
  - [ ] 3.2 Ensure list/0 returns all presets
  - [ ] 3.3 Ensure customize/2 works
  - [ ] 3.4 Ensure validate/1 works

- [ ] Step 4: Unit tests (8.2.4)
  - [ ] 4.1 Create test file
  - [ ] 4.2 Test all preset retrieval
  - [ ] 4.3 Test customization
  - [ ] 4.4 Test validation
  - [ ] 4.5 Test preset configurations

- [ ] Step 5: Documentation
  - [ ] 5.1 Update feature planning document with ✅
  - [ ] 5.2 Create summary document in notes/summaries/
  - [ ] 5.3 Update phase-08-integration.md plan

---

## References

- **Phase 8 Plan**: `notes/planning/accuracy/phase-08-integration.md`
- **PipelineConfig**: `lib/jido_ai/accuracy/pipeline_config.ex`
- **Pipeline**: `lib/jido_ai/accuracy/pipeline.ex`
- **Thresholds**: `lib/jido_ai/accuracy/thresholds.ex`
