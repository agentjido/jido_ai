# Feature Planning Document: Phase 2.4 - Tool-Based Verifiers

**Status:** ✅ Complete
**Section:** 2.4 - Tool-Based Verifiers
**Dependencies:** Phase 2.1 (Verifier Behaviors) - Complete, Phase 2.2 (Outcome Verifiers) - Complete, Phase 2.3 (PRM) - Complete
**Branch:** `feature/accuracy-phase-2-4-tool-verifiers`

## Problem Statement

The accuracy improvement system has:
- Candidate generation (Phase 1)
- Verifier interfaces (Phase 2.1)
- Outcome verifiers for final answer scoring (Phase 2.2)
- Process reward models for step-level verification (Phase 2.3)

However, it lacked **tool-based verification** capabilities for code generation. Without tool-based verifiers:

1. **No Code Execution Verification**: Cannot verify code by actually running it
2. **No Unit Test Validation**: Cannot verify code by running test suites
3. **No Static Analysis**: Cannot verify code quality using linters/type checkers
4. **Weaker Code Generation**: Code candidates cannot be empirically validated

**Impact**: Code generation candidates were only evaluated textually, missing opportunities for execution-based verification which is the gold standard for code correctness.

## Solution Overview

Implemented three tool-based verifiers that use external tooling to verify code candidates:

1. **`Jido.AI.Accuracy.Verifiers.CodeExecutionVerifier`** - Execute code in sandboxed environment
2. **`Jido.AI.Accuracy.Verifiers.UnitTestVerifier`** - Run unit tests and score by pass rate
3. **`Jido.AI.Accuracy.Verifiers.StaticAnalysisVerifier`** - Run linters/type checkers and score by issue severity
4. **`Jido.AI.Accuracy.ToolExecutor`** - Helper module for safe command execution

## Implementation Summary

### Files Created

**Implementation Files:**
- `lib/jido_ai/accuracy/tool_executor.ex` (335 lines) - Safe command execution with timeout handling
- `lib/jido_ai/accuracy/verifiers/code_execution_verifier.ex` (428 lines) - Code execution verification
- `lib/jido_ai/accuracy/verifiers/unit_test_verifier.ex` (548 lines) - Unit test verification
- `lib/jido_ai/accuracy/verifiers/static_analysis_verifier.ex` (349 lines) - Static analysis verification

**Test Files:**
- `test/jido_ai/accuracy/tool_executor_test.exs` (165 lines) - Tool executor tests
- `test/jido_ai/accuracy/verifiers/code_execution_verifier_test.exs` (390 lines) - Code execution tests
- `test/jido_ai/accuracy/verifiers/unit_test_verifier_test.exs` (400 lines) - Unit test verifier tests
- `test/jido_ai/accuracy/verifiers/static_analysis_verifier_test.exs` (465 lines) - Static analysis tests

### Features Implemented

#### ToolExecutor
- ✅ Port-based command execution
- ✅ Timeout handling with automatic termination
- ✅ Stdout/stderr capture
- ✅ Working directory validation
- ✅ Environment variable sanitization
- ✅ Optional Docker/podman sandboxing
- ✅ Exit code interpretation

#### CodeExecutionVerifier
- ✅ Language auto-detection (Python, JavaScript, Elixir, Ruby, Bash)
- ✅ Code extraction from markdown blocks
- ✅ Timeout-based execution limits
- ✅ Sandbox support (:none, :docker, :podman)
- ✅ Score based on exit code (1.0 for success, 0.5 for partial, 0.0 for failure)
- ✅ Expected output matching
- ✅ Comprehensive error reporting

#### UnitTestVerifier
- ✅ Multiple test output formats (JUnit XML, TAP, Dot)
- ✅ Auto-detection of test format
- ✅ Pass rate calculation (passed/total)
- ✅ Skipped test handling
- ✅ Configurable test commands and patterns
- ✅ Test file targeting from context
- ✅ Detailed failure reasoning

#### StaticAnalysisVerifier
- ✅ Configurable tool definitions
- ✅ JSON and text output parsing
- ✅ Severity-weighted scoring (error: 1.0, warning: 0.5, info: 0.1, style: 0.05)
- ✅ Multi-tool aggregation
- ✅ Custom severity weight support
- ✅ Issue metadata extraction

## Test Results

**All 229 tests passing** ✅

```
Finished in 1.9 seconds (1.9s async, 0.00s sync)
229 tests, 0 failures
```

### Test Coverage by Module

- **ToolExecutor**: Command execution, timeout handling, output capture, sandbox options
- **CodeExecutionVerifier**: Language detection, code execution, scoring, error handling
- **UnitTestVerifier**: TAP/JUnit/Dot parsing, pass rate calculation, batch verification
- **StaticAnalysisVerifier**: Issue parsing, severity weighting, multi-tool aggregation

## Quality Checks

- ✅ **Tests**: 229 tests, 0 failures
- ✅ **Formatting**: All files formatted with `mix format`
- ⚠️ **Credo**: 3 refactoring opportunities (code complexity warnings, not critical)
  - `detect_language/3` - cyclomatic complexity 21 (acceptable for pattern matching)
  - `verify/3` in CodeExecutionVerifier - nested depth 3 (reasonable for control flow)
  - `parse_dot/1` in UnitTestVerifier - nested depth 3 (acceptable for parsing logic)

## Usage Examples

### Code Execution Verifier

```elixir
verifier = CodeExecutionVerifier.new!(%{
  language: :python,
  timeout: 5000,
  sandbox: :none
})

candidate = Candidate.new!(%{
  content: """
  def add(a, b):
      return a + b
  print(add(2, 3))
  """
})

{:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})
# result.score => 1.0 (executed successfully)
# result.metadata.stdout => "5\n"
```

### Unit Test Verifier

```elixir
verifier = UnitTestVerifier.new!(%{
  test_command: "mix",
  test_args: ["test"],
  output_format: :tap
})

{:ok, result} = UnitTestVerifier.verify(verifier, candidate, %{})
# result.score => 0.8 (4 out of 5 tests passed)
# result.reasoning => "4/5 tests passed"
```

### Static Analysis Verifier

```elixir
verifier = StaticAnalysisVerifier.new!(%{
  tools: [
    %{name: "credo", command: "mix", args: ["credo"], output_format: :auto}
  ],
  severity_weights: %{error: 1.0, warning: 0.5, info: 0.1}
})

{:ok, result} = StaticAnalysisVerifier.verify(verifier, candidate, %{})
# result.score => 0.85 (based on issue severity)
# result.metadata.issues => list of found issues
```

## Known Limitations

1. **Behavior Callback Mismatch**: The verifiers implement `verify/3` and `verify_batch/3` but the behavior defines `verify/2` and `verify_batch/2`. This is an existing pattern in the codebase and generates warnings but is intentional for passing the verifier instance.

2. **Cross-Platform Differences**: Code execution behavior may vary slightly between operating systems due to shell differences.

3. **Sandbox Requirements**: Docker/podman sandboxing requires the container runtime to be installed and available in PATH.

## What Works

- ✅ All three verifiers correctly verify code candidates
- ✅ Unit tests provide comprehensive coverage
- ✅ ToolExecutor provides safe, timeout-limited command execution
- ✅ Multiple test output formats are correctly parsed
- ✅ Static analysis severity weighting works as expected
- ✅ Language detection for code execution works reliably
- ✅ Batch verification processes multiple candidates efficiently

## What's Next

The Phase 2.4 tool-based verifiers are complete and ready for integration. The next phase would be:

1. **Integration Testing**: Test verifiers with real code generation workflows
2. **Documentation**: Add user-facing documentation for verifier configuration
3. **Performance Optimization**: Consider parallel execution for batch operations
4. **Additional Language Support**: Extend language detection for more languages
