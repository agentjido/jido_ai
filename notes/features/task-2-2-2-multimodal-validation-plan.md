# Task 2.2.2: Multi-Modal Support Validation - Planning Document

**Date**: 2025-10-02
**Branch**: `feature/task-2-2-2-multimodal-validation`
**Status**: Planning

---

## Problem Statement

Multi-modal support detection is already implemented via the `modalities` field in the Model Registry (Phase 1). However, the accuracy and completeness of modality detection across all 57+ providers has not been validated. This task validates modality metadata and prepares for Phase 3's multi-modal implementation.

### Current State
- `modalities` field exists in `Jido.AI.Model` struct
- Registry extracts modalities from ReqLLM metadata
- Filtering by modality is implemented in `Registry.discover_models/1`
- No systematic validation of modality accuracy

### Issues to Address
1. **Unknown Accuracy**: No validation of vision/audio/document modality detection
2. **No Visibility**: No easy way to see which models support which modalities
3. **Missing Matrix**: No comprehensive view of modality support across providers
4. **Preparation Gap**: Phase 3 needs accurate modality data for implementation

---

## Solution Overview

Validate and document multi-modal support across all providers through systematic testing and reporting.

### Approach

**Layer 1: Individual Modality Validation** (Subtasks 2.2.2.1-2.2.2.3)
- Validate vision capability detection
- Validate audio capability detection
- Validate document processing indicators
- Generate validation reports per modality

**Layer 2: Comprehensive Matrix** (Subtask 2.2.2.4)
- Create modality compatibility matrix
- Show provider × modality support grid
- Identify multi-modal models
- Export as documentation

### Key Design Decisions

1. **Validation over Implementation**: This is Phase 2 validation, not Phase 3 implementation
2. **Leverage Existing Data**: Use ReqLLM modalities field, don't create new data
3. **Mix Task Approach**: Similar to Task 2.2.1's capability validation
4. **Documentation Focus**: Generate matrices for Phase 3 planning

---

## Technical Details

### Current Modality Implementation

**Model Structure** (`lib/jido_ai/model.ex`):
```elixir
typedstruct do
  field(:modalities, map())  # %{input: [...], output: [...]}
  # ...
end
```

**Modality Extraction** (`lib/jido_ai/model/registry/adapter.ex`):
```elixir
defp extract_modalities(info) do
  # Extracts from ReqLLM metadata
  # Returns: %{input: [:text, :image, :audio], output: [:text]}
end
```

**Modality Filtering** (`lib/jido_ai/model/registry.ex`):
```elixir
defp apply_single_filter(model, :modality, required_modality) do
  case model.modalities do
    nil -> required_modality == :text
    modalities ->
      input_modalities = Map.get(modalities, :input, [])
      required_modality in input_modalities
  end
end
```

### Modality Types

Based on ReqLLM and industry standards:

**Input Modalities**:
- `:text` - Text input (universal)
- `:image` - Image/vision input
- `:audio` - Audio input
- `:video` - Video input
- `:document` - Document processing (PDFs, etc.)

**Output Modalities**:
- `:text` - Text output (universal)
- `:image` - Image generation
- `:audio` - Audio generation

### File Locations

**Existing Files to Work With**:
- `lib/jido_ai/model.ex` - Model struct definition
- `lib/jido_ai/model/registry.ex` - Registry with modality filtering
- `lib/jido_ai/model/registry/adapter.ex` - Modality extraction logic

**New Files to Create**:
- `lib/mix/tasks/jido.validate.modalities.ex` - Validation Mix task
- `lib/jido_ai/model/modality_matrix.ex` - Matrix generation module
- `test/jido_ai/model/modality_validation_test.exs` - Validation tests

---

## Success Criteria

### Subtask 2.2.2.1 - Vision Capability Detection
- [ ] Identify all models with vision/image input capabilities
- [ ] Validate vision models are correctly marked
- [ ] Generate vision capability report
- [ ] Accuracy >90% for known vision models

### Subtask 2.2.2.2 - Audio Capability Detection
- [ ] Identify all models with audio input capabilities
- [ ] Validate audio models are correctly marked
- [ ] Generate audio capability report
- [ ] Accuracy >90% for known audio models

### Subtask 2.2.2.3 - Document Processing Indicators
- [ ] Identify models with document processing capabilities
- [ ] Validate document models are correctly marked
- [ ] Generate document processing report
- [ ] Document common patterns

### Subtask 2.2.2.4 - Modality Compatibility Matrix
- [ ] Generate provider × modality matrix
- [ ] Show input/output modality support
- [ ] Identify multi-modal models (2+ input modalities)
- [ ] Export as Markdown documentation
- [ ] Save to `notes/modality-compatibility-matrix.md`

### Overall Success
- [ ] Mix task runs successfully
- [ ] All modality types validated
- [ ] Compatibility matrix generated
- [ ] Documentation ready for Phase 3

---

## Implementation Plan

### Subtask 2.2.2.1: Validate Vision Capability Detection

**Goal**: Validate that vision/image input models are correctly detected and marked.

#### Step 1: Create Vision Validation Logic
- Query all models with `:image` in input modalities
- Cross-reference with known vision models (GPT-4V, Claude 3 Sonnet, Gemini Pro Vision, etc.)
- Identify false positives and false negatives
- Calculate accuracy percentage

**Files to create/modify**:
- Create validation logic in Mix task

**Tests**:
- Validate GPT-4V detected as vision model
- Validate Claude 3 Sonnet detected as vision model
- Validate text-only models NOT marked as vision

#### Step 2: Generate Vision Report
- List all vision-capable models
- Group by provider
- Show input modality details
- Calculate statistics

**Deliverables**:
- Vision capability validation report
- Accuracy metrics

---

### Subtask 2.2.2.2: Validate Audio Capability Detection

**Goal**: Validate that audio input models are correctly detected and marked.

#### Step 1: Create Audio Validation Logic
- Query all models with `:audio` in input modalities
- Cross-reference with known audio models (Whisper, etc.)
- Identify accuracy

**Files to create/modify**:
- Add audio validation to Mix task

**Tests**:
- Validate Whisper detected as audio model
- Validate audio-capable multimodal models detected

#### Step 2: Generate Audio Report
- List all audio-capable models
- Show provider support
- Calculate statistics

**Deliverables**:
- Audio capability validation report
- Accuracy metrics

---

### Subtask 2.2.2.3: Validate Document Processing Indicators

**Goal**: Validate document processing capability indicators.

#### Step 1: Identify Document Processing Models
- Look for `:document` modality or document-related capabilities
- Check for PDF processing, OCR capabilities
- Identify patterns in model names/descriptions

**Files to create/modify**:
- Add document validation to Mix task

**Tests**:
- Validate document-capable models detected
- Check metadata patterns

#### Step 2: Generate Document Report
- List document processing models
- Show capability indicators
- Document common patterns

**Deliverables**:
- Document processing validation report
- Pattern documentation

---

### Subtask 2.2.2.4: Generate Comprehensive Modality Compatibility Matrix

**Goal**: Create a comprehensive matrix showing modality support across all providers.

#### Step 1: Create Matrix Generation Module
- Build provider × modality grid
- Calculate totals and percentages
- Identify multi-modal models

**Files to create**:
- `lib/jido_ai/model/modality_matrix.ex`

**Functions**:
```elixir
def generate_matrix(models)
def format_as_markdown(matrix)
def identify_multimodal_models(models)
```

**Tests**:
- Matrix generation works
- Markdown formatting correct
- Multi-modal identification accurate

#### Step 2: Create Mix Task for Full Validation
- Integrate all validation logic
- Run vision, audio, document validations
- Generate compatibility matrix
- Save matrix to file

**Files to create**:
- `lib/mix/tasks/jido.validate.modalities.ex`

**Usage**:
```bash
mix jido.validate.modalities
mix jido.validate.modalities --modality vision
mix jido.validate.modalities --provider anthropic
mix jido.validate.modalities --export notes/modality-matrix.md
```

**Tests**:
- Mix task runs without errors
- All modalities validated
- Matrix exported successfully

#### Step 3: Generate Documentation
- Create modality compatibility matrix document
- Include provider statistics
- List multi-modal models
- Save to `notes/modality-compatibility-matrix.md`

**Deliverables**:
- Comprehensive modality matrix
- Multi-modal models list
- Provider statistics
- Markdown documentation

---

## Notes and Considerations

### Edge Cases

1. **Missing Modality Data**
   - Some models may not have modality metadata
   - Assume text-only when missing
   - Log warnings for investigation

2. **Modality Naming Variations**
   - Different providers may use different terms
   - Normalize to standard set: text, image, audio, video, document
   - Handle string vs atom variations

3. **Multi-Modal Models**
   - Models with 2+ input modalities need special attention
   - These are highest value for Phase 3
   - Track separately in reports

### Known Multi-Modal Models

From industry knowledge:
- **Vision**: GPT-4V, GPT-4o, Claude 3 Opus/Sonnet, Gemini Pro Vision, Gemini 1.5 Pro
- **Audio**: Whisper (if available), some GPT-4o variants
- **Multi-modal**: GPT-4o (text+image+audio), Gemini 1.5 Pro (text+image+audio+video)

### Validation Approach

**Accuracy Calculation**:
```elixir
accuracy = (correctly_detected / total_known_models) * 100
```

**Known Models List**:
- Maintain list of known vision models for validation
- Maintain list of known audio models
- Update based on ReqLLM metadata

### Performance Considerations

- Validation should complete in <30 seconds
- Matrix generation should handle 2000+ models
- Use existing Registry queries (already optimized with index from Task 2.2.1)

### Future Enhancements (Phase 3)

This validation prepares for:
- Phase 3.1: Vision input implementation
- Phase 3.2: Audio input implementation
- Phase 3.3: Document processing
- Phase 3.4: Multi-modal request handling

---

## Deliverables Summary

### Code Artifacts
1. `lib/mix/tasks/jido.validate.modalities.ex` - Validation Mix task
2. `lib/jido_ai/model/modality_matrix.ex` - Matrix generation (optional module)
3. `test/jido_ai/model/modality_validation_test.exs` - Tests

### Documentation
1. `notes/modality-compatibility-matrix.md` - Comprehensive matrix
2. Vision validation report (within matrix doc)
3. Audio validation report (within matrix doc)
4. Document processing report (within matrix doc)

### Validation Reports
- Vision capability accuracy
- Audio capability accuracy
- Document processing detection
- Overall modality coverage statistics

---

## Implementation Strategy

**Simple Approach** (Recommended):
- Single Mix task handles all validation
- Output comprehensive report to terminal
- Optionally export to Markdown file
- Leverage existing Registry queries

**Modular Approach** (If needed):
- Separate module for matrix generation
- Separate functions per modality type
- More testable but more complex

**Recommendation**: Start simple with single Mix task, refactor if needed.

---

## Timeline Estimate

- Subtask 2.2.2.1: Vision validation - 30 min
- Subtask 2.2.2.2: Audio validation - 20 min
- Subtask 2.2.2.3: Document validation - 20 min
- Subtask 2.2.2.4: Matrix generation - 45 min
- Testing and documentation - 30 min
- **Total**: ~2.5 hours

---

## Conclusion

Task 2.2.2 validates multi-modal support across all providers, creating visibility into vision, audio, and document processing capabilities. The compatibility matrix and validation reports prepare the foundation for Phase 3's multi-modal implementation.

**Key Focus**: Validation and documentation, not implementation. Phase 3 will handle actual multi-modal request processing.
