# Feature: Task-Specific Evaluators Implementation

## Problem Statement

Currently, GEPA has only one fully implemented task-specific evaluator (CodeEvaluator). The remaining four task types fall back to generic evaluation:
- `:reasoning` - Mathematical and logical reasoning
- `:classification` - Text categorization and labeling
- `:summarization` - Text condensation
- `:question_answering` - QA and information retrieval

This limits GEPA's effectiveness for these task types since generic evaluation doesn't account for task-specific quality metrics.

## Solution Overview

Implement four specialized evaluators following the strategy pattern established by CodeEvaluator. Each evaluator will:
1. Provide task-specific fitness calculation
2. Include domain-specific validation
3. Return enhanced metrics in evaluation results
4. Integrate seamlessly with the TaskEvaluator dispatcher

## Technical Details

### File Structure
```
lib/jido_ai/runner/gepa/evaluation/strategies/
├── code_evaluator.ex (existing)
├── reasoning_evaluator.ex (new)
├── classification_evaluator.ex (new)
├── summarization_evaluator.ex (new)
└── question_answering_evaluator.ex (new)

test/jido_ai/runner/gepa/evaluation/strategies/
├── code_evaluator_test.exs (existing)
├── reasoning_evaluator_test.exs (new)
├── classification_evaluator_test.exs (new)
├── summarization_evaluator_test.exs (new)
└── question_answering_evaluator_test.exs (new)
```

### Evaluator Specifications

#### 1. ReasoningEvaluator
**Purpose**: Evaluate mathematical and logical reasoning tasks

**Fitness Components**:
- Correctness: 60% - Answer matches expected result
- Reasoning quality: 25% - Includes step-by-step explanation
- Clarity: 15% - Explanation is clear and well-structured

**Validation**:
- Check for presence of reasoning steps
- Validate answer format (numeric, boolean, etc.)
- Detect hallucination indicators (contradictions, unsupported claims)

**Enhanced Metrics**:
```elixir
%{
  reasoning_steps_present: boolean(),
  answer_correctness: float(),
  explanation_clarity: float(),
  answer_format_valid: boolean()
}
```

#### 2. ClassificationEvaluator
**Purpose**: Evaluate text classification and categorization tasks

**Fitness Components**:
- Label accuracy: 70% - Correct classification
- Confidence appropriateness: 20% - Confidence matches actual accuracy
- Consistency: 10% - Similar inputs get similar classifications

**Validation**:
- Verify label is in expected set (if provided)
- Check confidence score format (0.0-1.0)
- Detect label hallucination (creating non-existent categories)

**Enhanced Metrics**:
```elixir
%{
  label_accuracy: float(),
  confidence_calibration: float(),
  classification_consistency: float(),
  valid_label: boolean()
}
```

#### 3. SummarizationEvaluator
**Purpose**: Evaluate text summarization quality

**Fitness Components**:
- Factual consistency: 40% - Summary reflects source content
- Conciseness: 30% - Appropriate length relative to source
- Coherence: 20% - Flows logically, well-structured
- Coverage: 10% - Captures key points

**Validation**:
- Check summary length is shorter than source
- Detect factual hallucinations (info not in source)
- Verify summary is not just truncation

**Enhanced Metrics**:
```elixir
%{
  factual_consistency: float(),
  length_ratio: float(),
  coherence_score: float(),
  key_points_coverage: float(),
  is_truncation: boolean()
}
```

#### 4. QuestionAnsweringEvaluator
**Purpose**: Evaluate QA and information retrieval tasks

**Fitness Components**:
- Answer accuracy: 60% - Correct information provided
- Relevance: 25% - Directly addresses the question
- Completeness: 15% - Provides sufficient detail

**Validation**:
- Check answer is non-empty
- Verify answer addresses question type (who/what/when/where/why/how)
- Detect hallucinated information

**Enhanced Metrics**:
```elixir
%{
  answer_accuracy: float(),
  relevance_score: float(),
  completeness_score: float(),
  question_type_match: boolean(),
  contains_hallucination: boolean()
}
```

## Implementation Plan

### Phase 1: ReasoningEvaluator
1. Create `reasoning_evaluator.ex` module
2. Implement `evaluate_prompt/2` function
3. Add reasoning-specific fitness calculation
4. Implement validation logic
5. Create comprehensive test suite
6. Update TaskEvaluator dispatcher
7. Run tests to verify integration

### Phase 2: ClassificationEvaluator
1. Create `classification_evaluator.ex` module
2. Implement `evaluate_prompt/2` function
3. Add classification-specific fitness calculation
4. Implement label validation logic
5. Create comprehensive test suite
6. Update TaskEvaluator dispatcher
7. Run tests to verify integration

### Phase 3: SummarizationEvaluator
1. Create `summarization_evaluator.ex` module
2. Implement `evaluate_prompt/2` function
3. Add summarization-specific fitness calculation
4. Implement factual consistency checking
5. Create comprehensive test suite
6. Update TaskEvaluator dispatcher
7. Run tests to verify integration

### Phase 4: QuestionAnsweringEvaluator
1. Create `question_answering_evaluator.ex` module
2. Implement `evaluate_prompt/2` function
3. Add QA-specific fitness calculation
4. Implement answer validation logic
5. Create comprehensive test suite
6. Update TaskEvaluator dispatcher
7. Run tests to verify integration

### Phase 5: Final Integration
1. Run complete test suite
2. Fix any integration issues
3. Update GEPA documentation with new evaluators
4. Create examples for each evaluator type

## Success Criteria

- [ ] All 4 evaluators implemented following CodeEvaluator pattern
- [ ] Each evaluator has comprehensive test coverage
- [ ] TaskEvaluator dispatcher updated to use new evaluators
- [ ] All tests passing (unit and integration)
- [ ] No Credo warnings introduced
- [ ] Documentation updated to reflect new capabilities

## Dependencies

- Existing: `Jido.AI.Runner.GEPA.Evaluator` (generic evaluator)
- Existing: `Jido.AI.Runner.GEPA.Evaluation.TaskEvaluator` (dispatcher)
- Pattern: `Jido.AI.Runner.GEPA.Evaluation.Strategies.CodeEvaluator` (reference implementation)

## Limitations & Future Work

**Current Limitations**:
- Evaluation is heuristic-based, not using reference-based metrics (BLEU, ROUGE, etc.)
- No external validation tools (fact-checkers, reasoning validators)
- Limited to string-based analysis

**Future Enhancements**:
- Add reference-based metrics for summarization (ROUGE scores)
- Integrate external reasoning validators (symbolic solvers)
- Add multi-language support for classification
- Implement ensemble evaluation (multiple models voting)

## Notes

- Each evaluator should follow the same pattern as CodeEvaluator
- Use Logger.debug for detailed evaluation steps
- Include comprehensive doctests in each module
- Weight components should sum to 1.0
- All evaluators must handle nil/empty responses gracefully
