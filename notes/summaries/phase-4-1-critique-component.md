# Phase 4.1 - Critique Component - Summary

**Date**: 2025-01-12
**Branch**: `feature/accuracy-phase-4-1-critique`
**Status**: Complete

## Overview

Implemented the critique component for the accuracy improvement system. This enables
self-reflection capabilities where the system can analyze its own responses, identify
issues, and provide actionable feedback for iterative refinement.

## What Was Implemented

### 1. CritiqueResult (`lib/jido_ai/accuracy/critique_result.ex`)

A structured data type for holding critique results:

- `:issues` - List of identified issues
- `:suggestions` - List of improvement suggestions
- `:severity` - Overall severity score (0.0-1.0)
- `:feedback` - Natural language feedback
- `:actionable` - Whether issues are actionable
- `:metadata` - Additional metadata

Key functions:
- `new/1`, `new!/1` - Constructors with validation
- `has_issues?/1` - Check if issues present
- `should_refine?/2` - Check if severity above threshold
- `severity_level/1` - Convert severity to :low/:medium/:high
- `merge/2` - Combine multiple critique results
- `add_issue/2` - Add an issue to a result

### 2. Critique Behavior (`lib/jido_ai/accuracy/critique.ex`)

Interface for critique generators:

- `@callback critique/2` - Generate critique for a candidate
- `@callback critique_batch/2` - Generate critiques for multiple candidates (optional)
- `critiquer?/1` - Check if module implements the behavior
- `critique_batch/3` - Default batch implementation

### 3. LLMCritiquer (`lib/jido_ai/accuracy/critiquers/llm_critiquer.ex`)

LLM-based critique that uses an LLM to analyze candidate responses:

Configuration:
- `:model` - Model to use for critique
- `:prompt_template` - Custom EEx template for critique prompt
- `:temperature` - Temperature for LLM calls
- `:timeout` - Timeout for LLM calls
- `:domain` - Optional domain for specialized critique (:math, :code, :writing, :reasoning)

Features:
- Structured JSON output parsing with fallback
- Domain-specific guidelines
- Content sanitization for security

### 4. ToolCritiquer (`lib/jido_ai/accuracy/critiquers/tool_critiquer.ex`)

Tool-based critique that executes external tools and aggregates results:

Configuration:
- `:tools` - List of tool specifications (name, command, args, severity_on_fail)
- `:severity_map` - Custom severity mapping
- `:timeout` - Timeout per tool
- `:working_dir` - Working directory for tool execution

Features:
- Executes tools sequentially via ToolExecutor
- Aggregates results into unified critique
- Custom output parsers per tool
- Graceful failure handling

## Test Coverage

| File | Tests |
|------|-------|
| `critique_result_test.exs` | 38 |
| `critique_test.exs` | 12 |
| `llm_critiquer_test.exs` | 18 |
| `tool_critiquer_test.exs` | 19 |
| **Total** | **87** |

All tests passing (0 failures).

## Key Design Decisions

1. **Severity Scoring**: 0.0-1.0 scale with qualitative levels
   - 0.0-0.3: Low (minor issues)
   - 0.3-0.7: Medium (notable issues)
   - 0.7-1.0: High (critical issues)

2. **Behavior Pattern**: Allows pluggable critique strategies
   - Both module-level (2-arg) and struct-based (3-arg) implementations supported
   - `critiquer?/1` checks for either `critique/2` or `critique/3`

3. **JSON Parsing with Fallback**: LLMCritiquer handles various response formats
   - Primary: JSON in code blocks
   - Fallback: Regex extraction from text

4. **Tool Integration**: ToolCritiquer leverages existing ToolExecutor
   - Safe command execution with allowlist
   - Timeout handling
   - Working directory management

## Files Created

### Source Files
- `lib/jido_ai/accuracy/critique.ex`
- `lib/jido_ai/accuracy/critique_result.ex`
- `lib/jido_ai/accuracy/critiquers/llm_critiquer.ex`
- `lib/jido_ai/accuracy/critiquers/tool_critiquer.ex`

### Test Files
- `test/jido_ai/accuracy/critique_test.exs`
- `test/jido_ai/accuracy/critique_result_test.exs`
- `test/jido_ai/accuracy/critiquers/llm_critiquer_test.exs`
- `test/jido_ai/accuracy/critiquers/tool_critiquer_test.exs`

### Documentation
- `notes/features/accuracy-phase-4-1-critique.md` (planning document)

## Usage Examples

### LLMCritiquer

```elixir
critiquer = LLMCritiquer.new!(domain: :code)
candidate = Candidate.new!(%{id: "1", content: "def foo() return end"})

{:ok, critique} = LLMCritiquer.critique(critiquer, candidate, %{
  prompt: "Write a function to return 42"
})

critique.severity      # => 0.7
critique.issues        # => ["Syntax error: missing end"]
critique.suggestions   # => ["Add 'end' keyword"]
```

### ToolCritiquer

```elixir
critiquer = ToolCritiquer.new!(tools: [
  %{name: "linter", command: "mix", args: ["credo"], severity_on_fail: 0.7}
])

{:ok, critique} = ToolCritiquer.critique(critiquer, candidate, %{
  working_dir: "/path/to/project"
})

critique.feedback  # => "Some tools failed: linter (0/1 passed)"
```

## Next Steps

Phase 4.1 is complete. The critique component provides:
- Foundation for self-refine patterns
- Structured feedback for response improvement
- Tool-based verification critique
- LLM-based analysis

This enables future work on:
- Self-refine loops
- Reflexion pattern implementation
- Multi-turn revision processes
