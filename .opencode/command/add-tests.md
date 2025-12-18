---
name: add-tests
description: Create comprehensive test coverage using systematic methodology and expert consultation
agents:
  - test-developer
  - elixir-expert
  - research-agent
  - consistency-reviewer
  - qa-reviewer
---

# Add Tests - Systematic Test Development

Creates comprehensive test coverage using proven methodology while consulting language-specific experts and ensuring consistency with existing patterns.

## Workflow

### 1. Invoke Test-Developer

The `test-developer` agent orchestrates systematic test development:

1. **Analyzes your project** - Determines language/framework and patterns
2. **Consults language experts** - Gets specific guidance for your stack
3. **Checks existing patterns** - Ensures consistency with codebase
4. **Applies methodology** - Guides incremental test development
5. **Ensures quality** - Coordinates coverage assessment

### 2. Project Analysis Phase

The `test-developer` performs initial analysis:

```bash
# Identify testing framework
# For Elixir
mix test --version

# For JavaScript
npm test -- --version

# For Python
pytest --version

# Analyze existing test structure
ls -la test/
find test -name "*_test.*" | head -10
```

Determines:
- Programming language and framework
- Testing tools in use
- Existing test patterns
- Coverage requirements

### 3. Expert Consultation

Based on project type, consults appropriate experts:

#### For Elixir Projects
`elixir-expert` provides:
- ExUnit best practices
- Phoenix/Ash testing patterns
- Mimic mocking guidance (use `expect`, not `stub`)
- Generator patterns for test data

#### For Other Languages
`research-agent` provides:
- Framework-specific testing approaches
- Best practices documentation
- Mocking strategies
- Test organization patterns

#### For All Projects
`consistency-reviewer` ensures:
- Tests follow existing patterns
- Naming conventions match
- File organization aligns
- Style consistency maintained

### 4. Test Architecture Planning

The `test-developer` creates comprehensive plan:

#### Coverage Mapping
```markdown
## Test Coverage Requirements

### Success Paths
- [ ] Main workflow success scenarios
- [ ] Valid input handling
- [ ] Expected state transitions

### Error Conditions
- [ ] Invalid input handling
- [ ] External service failures
- [ ] Resource exhaustion scenarios

### Edge Cases
- [ ] Boundary conditions
- [ ] Concurrent operations
- [ ] Empty/null handling
```

#### Test Data Strategy
```elixir
# Example for Elixir
def user_generator(opts \\ []) do
  seed_generator(
    %User{
      name: sequence(:name, &"User #{&1}"),
      email: sequence(:email, &"user#{&1}@test.com")
    },
    overrides: opts
  )
end
```

#### Mock Strategy
- Mock only external boundaries
- Never mock internal business logic
- Use consistent mocking patterns
- Follow existing project conventions

### 5. Incremental Implementation

Focus-driven development approach:

#### Step 1: Core Success Path
```elixir
# Elixir example with focus
@tag :focus
test "main workflow succeeds with valid input" do
  # Setup with generators
  user = generate(user_generator())
  
  # Single action under test
  {:ok, result} = MyModule.process(user)
  
  # Assertions
  assert result.status == :success
end

# Run focused test
mix test --only focus
```

#### Step 2: Build Coverage
1. Start with success path
2. Add error conditions
3. Cover edge cases
4. Add integration tests
5. Verify with coverage tools

#### Step 3: Remove Focus Tags
```bash
# After test passes, remove focus
# Continue with next test
```

### 6. Quality Verification

The `test-developer` coordinates with `qa-reviewer`:

```bash
# Check coverage metrics
mix test --cover  # Elixir
npm test -- --coverage  # JavaScript
pytest --cov  # Python

# Verify test quality
- Actual assertions (not placeholders)
- External dependencies mocked
- Test data properly generated
- Both success and failure paths
```

### 7. Test Organization

Maintain clear structure:

```
test/
├── unit/
│   ├── models/
│   └── services/
├── integration/
│   └── api/
├── support/
│   ├── generators.ex
│   └── test_helpers.ex
└── e2e/
    └── workflows/
```

## Success Criteria

The test-developer ensures:

### Coverage Completeness
- ✅ All public APIs tested
- ✅ Success paths covered
- ✅ Error conditions handled
- ✅ Edge cases addressed
- ✅ Integration points validated

### Test Quality
- ✅ Tests actually validate behavior
- ✅ No placeholder/stub tests
- ✅ External boundaries mocked
- ✅ Test data properly generated
- ✅ Tests run quickly and reliably

### Pattern Consistency
- ✅ Follows existing conventions
- ✅ Naming patterns match
- ✅ Organization consistent
- ✅ Mock patterns aligned

## Example Usage Flow

```markdown
1. Start: "Add tests for authentication feature"

2. Analysis:
   - Language: Elixir/Phoenix
   - Framework: ExUnit
   - Existing patterns: Generators, Mimic mocks

3. Consultation:
   - elixir-expert: ExUnit best practices
   - consistency-reviewer: Existing test patterns

4. Planning:
   - Success: Login, logout, session
   - Errors: Invalid credentials, expired tokens
   - Edge: Concurrent logins, rate limiting

5. Implementation:
   - Step 1: Login success test ✅
   - Step 2: Invalid credentials test ✅
   - Step 3: Session management tests ✅
   - Step 4: Integration tests ✅

6. Verification:
   - Coverage: 95%
   - All tests passing
   - Patterns consistent
```

## Notes

- This command delegates to test-developer for systematic approach
- Language experts provide framework-specific guidance
- Focus-driven development prevents overwhelming complexity
- Incremental approach ensures steady progress
- Quality verification prevents incomplete testing
