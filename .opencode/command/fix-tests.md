---
name: fix-tests
description: Systematically diagnose and fix failing tests using proven methodology and expert consultation
agents:
  - test-fixer
  - elixir-expert
  - research-agent
  - qa-reviewer
  - consistency-reviewer
---

# Fix Tests - Systematic Test Failure Resolution

Systematically diagnoses and fixes failing tests using proven debugging methodology while consulting language-specific experts and maintaining test suite integrity.

## Workflow

### 1. Initial Test Failure Discovery

Run comprehensive test analysis to identify failures:

```bash
# For Elixir projects
mix test --seed 0

# For JavaScript projects
npm test

# For Python projects
pytest

# General - capture failure output
[test-command] 2>&1 | tee test-results.log
```

### 2. Invoke Test-Fixer Agent

The `test-fixer` agent orchestrates systematic resolution:

1. **Analyzes test failures** comprehensively
2. **Categorizes failures** by type and priority
3. **Consults language experts** for debugging guidance
4. **Applies systematic resolution** methodology
5. **Ensures quality** through continuous validation

### 3. Expert Consultation Phase

Based on project type, `test-fixer` consults appropriate experts:

**For Elixir Projects:**
- `elixir-expert` for ExUnit, Ash, Phoenix, and Ecto patterns
- Guidance on Mimic mocking, generators, and test structure

**For Other Languages:**
- `research-agent` for framework-specific debugging approaches
- Documentation on testing best practices

**For All Projects:**
- `consistency-reviewer` for pattern alignment
- `qa-reviewer` for test quality validation

### 4. Systematic Resolution Process

The `test-fixer` follows this prioritized approach:

#### Failure Prioritization Framework

1. **Critical Infrastructure** - Test setup, generators, shared utilities
2. **Blocking Failures** - Tests preventing others from running
3. **Core Functionality** - Main workflow and business logic tests
4. **Integration Tests** - External service and end-to-end tests
5. **Edge Cases** - Boundary conditions and error scenarios

#### Focus-Driven Debugging

Isolate and fix one test at a time:

```elixir
# Elixir example
@tag :focus
test "specific failing test" do
  # test implementation
end

# Run focused test
mix test --only focus --trace
```

```javascript
// JavaScript example
test.only('specific failing test', () => {
  // test implementation
});
```

#### Root Cause Investigation

For each failing test:
1. Capture complete error information
2. Trace failure path from error backwards
3. Add debugging output to understand state
4. Identify root cause vs symptoms
5. Consult experts for proper fix approach

### 5. Fix Implementation

Based on root cause and expert guidance:

#### Common Fix Patterns

**Test Data Issues:**
- Update generators with missing required fields
- Fix data relationships and associations
- Ensure unique constraints are satisfied

**Mock/Stub Issues:**
- Correct mock signatures to match actual functions
- Fix return values and error responses
- Ensure proper mock cleanup between tests

**Timing/Async Issues:**
- Add appropriate waits for async operations
- Fix race conditions
- Ensure proper test isolation

**Assertion Issues:**
- Update assertions for changed behavior
- Fix expected values
- Correct comparison logic

### 6. Verification Process

After each fix:

```bash
# Verify focused test passes
[test-command] --only focus

# Check related tests
[test-command] [related-test-file]

# Run broader test suite
[test-command]

# Quality checks (Elixir example)
mix format
mix credo --strict
mix dialyzer
```

### 7. Progress Tracking

Track resolution systematically:

```markdown
## Test Fix Progress

### Fixed ✅
- [x] Test: user_authentication_test.exs:45
  - Issue: Missing mock for email service
  - Fix: Added proper expect() with correct signature
  - Verified: All auth tests passing

### In Progress 🚧
- [ ] Test: guild_creation_test.exs:78
  - Issue: Investigating generator issue
  - Next: Update guild_generator with required fields

### Remaining ❌
- [ ] integration_test.exs:23
- [ ] edge_case_test.exs:89
```

### 8. Final Validation

Before considering complete:

```bash
# Run full test suite multiple times with different seeds
# Elixir
mix test --seed 0
mix test --seed 42
mix test --seed 999

# Check for leftover focus tags
grep -r "@tag.*:focus\|\.only\|test\.skip" test/

# Verify no debug statements
grep -r "IO\.inspect\|console\.log\|debugger\|pry" test/
```

## Success Criteria

The test-fixer ensures:

### Resolution Quality
- ✅ Root causes fixed, not just symptoms
- ✅ Language-appropriate patterns used
- ✅ No new test failures introduced
- ✅ Pattern consistency maintained
- ✅ Expert guidance followed

### Test Suite Health
- ✅ All tests passing consistently
- ✅ No flaky tests remaining
- ✅ Test isolation maintained
- ✅ Proper cleanup implemented
- ✅ Performance acceptable

## Error Handling

### No Tests Found

```markdown
❌ No test files found

Verify test directory exists and contains test files:
- Elixir: test/*.exs
- JavaScript: **/*.test.js, **/*.spec.js
- Python: test_*.py, *_test.py
```

### Persistent Failures

```markdown
⚠️ Test continues to fail after fix attempt

Consider:
- Deeper root cause investigation
- Consulting additional experts
- Reviewing recent code changes
- Checking environment dependencies
```

### Expert Consultation Issues

```markdown
⚠️ Unable to determine project type

Please specify the testing framework:
- ExUnit (Elixir)
- Jest/Mocha (JavaScript)
- pytest/unittest (Python)
- Other: [specify]
```

## Key Benefits

- **Systematic approach**: Proven methodology for any language
- **Expert guidance**: Language-specific best practices
- **Focus-driven**: One test at a time for clarity
- **Root cause focus**: Fixes underlying issues
- **Quality assurance**: Continuous validation
- **Progress tracking**: Clear visibility of resolution

## Notes

- This command delegates to the test-fixer agent for comprehensive resolution
- Language experts provide framework-specific guidance
- Focus-driven debugging prevents context switching
- Root cause analysis ensures lasting fixes
- Progress tracking maintains momentum
