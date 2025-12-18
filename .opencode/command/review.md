---
name: review
description: Conduct comprehensive pull request review comparing current branch against main
agents:
  - factual-reviewer
  - qa-reviewer
  - senior-engineer-reviewer
  - security-reviewer
  - consistency-reviewer
  - redundancy-reviewer
  - elixir-reviewer
  - documentation-reviewer
---

# Pull Request Review

Conducts a comprehensive pull request review comparing the current branch against main, verifying implementation matches planning documents and meets quality standards.

## Workflow

### 1. Context Gathering

Analyze the pull request context:

```bash
# Get current branch
git branch --show-current

# Show diff summary against main
git diff main --stat

# List changed files
git diff main --name-only
```

Locate and read the planning document:
- Feature branches → `notes/features/<feature_name>.md`
- Fix branches → `notes/fixes/<fix_name>.md`
- Task branches → `notes/tasks/<task_name>.md`

### 2. Parallel Review Agent Execution

Run all applicable review agents simultaneously for multi-perspective analysis:

#### Core Review Agents (Always Run)

**`factual-reviewer`**: Implementation vs Planning Verification
- Compares actual implementation against planning document
- Identifies deviations from documented requirements
- Verifies claimed functionality is implemented
- Checks if success criteria are met

**`qa-reviewer`**: Testing Coverage and Quality
- Analyzes test coverage for new features
- Verifies edge cases and error scenarios
- Checks test quality and effectiveness
- Identifies missing test scenarios

**`senior-engineer-reviewer`**: Architecture and Design
- Assesses architectural decisions
- Reviews system integration
- Evaluates long-term maintainability
- Checks scalability implications

**`security-reviewer`**: Security Analysis
- Identifies potential vulnerabilities
- Reviews authentication/authorization
- Checks for exposed secrets
- Validates input sanitization

**`consistency-reviewer`**: Pattern Consistency
- Verifies adherence to codebase patterns
- Checks naming conventions
- Reviews code organization
- Ensures style consistency

**`redundancy-reviewer`**: Code Duplication
- Identifies duplicate code blocks
- Finds refactoring opportunities
- Suggests consolidation approaches
- Reviews code efficiency

#### Language-Specific Reviewers

**For Elixir/Phoenix/Ash/Ecto changes:**

**`elixir-reviewer`**: Comprehensive Elixir Analysis
- Runs `mix format --check-formatted`
- Executes `mix credo --strict`
- Performs `mix dialyzer` analysis
- Security scan with `mix sobelow`
- Dependency audit with `mix deps.audit`
- Test execution and coverage analysis

**`documentation-reviewer`**: Documentation Quality
- Verifies documentation completeness
- Checks README updates
- Reviews inline documentation
- Validates API documentation

### 3. Review Synthesis

After all agents complete their analysis, synthesize findings into a comprehensive report:

```markdown
# Pull Request Review Report

## Branch: [branch-name]
## Planning Document: [path/to/plan.md]

## Executive Summary
[High-level assessment of the PR]

## 🚨 Blockers (Must Fix Before Merge)

### [Category: Security/Logic/Testing/etc.]
- **File**: [filename:line]
- **Issue**: [Specific problem]
- **Impact**: [Why this blocks merge]
- **Fix**: [Required action]

## ⚠️ Concerns (Should Address or Explain)

### [Category]
- **File**: [filename:line]
- **Issue**: [Concern description]
- **Suggestion**: [How to address]

## 💡 Suggestions (Nice to Have)

### [Category]
- **File**: [filename:line]
- **Enhancement**: [Improvement suggestion]
- **Benefit**: [Why this would help]

## ✅ Good Practices Noticed

### [Category]
- **File**: [filename]
- **Practice**: [What was done well]
- **Impact**: [Positive effect]

## Detailed Analysis

### Implementation vs Planning
[Factual-reviewer findings]
- Planning adherence: [X]%
- Deviations identified: [List]
- Missing requirements: [List]

### Test Coverage
[QA-reviewer findings]
- Coverage: [X]%
- Missing scenarios: [List]
- Test quality assessment: [Summary]

### Architecture & Design
[Senior-engineer-reviewer findings]
- Architectural fit: [Assessment]
- Scalability concerns: [List]
- Maintainability score: [X/10]

### Security
[Security-reviewer findings]
- Vulnerabilities found: [Count]
- Risk level: [High/Medium/Low]
- Required fixes: [List]

### Code Quality
[Consistency-reviewer findings]
- Pattern violations: [Count]
- Style issues: [Count]
- Naming inconsistencies: [List]

### Code Efficiency
[Redundancy-reviewer findings]
- Duplication found: [X]%
- Refactoring opportunities: [Count]
- Consolidation suggestions: [List]

### Language-Specific (Elixir)
[Elixir-reviewer findings]
- Format issues: [Count]
- Credo warnings: [Count]
- Dialyzer issues: [Count]
- Security concerns: [Count]
```

### 4. Review Categories

Evaluate each category systematically:

#### Code Quality & Standards
- Established patterns and conventions
- Naming consistency
- Code formatting and readability
- Code smells and anti-patterns
- Complexity assessment

#### Testing
- Feature and bug fix coverage
- Test effectiveness
- Edge case coverage
- Test suite integrity
- Coverage adequacy

#### Functionality & Logic
- Implementation matches planning
- Deviation justification
- Bug and logic error detection
- Error handling
- Input validation
- Performance considerations

#### Security & Best Practices
- Vulnerability assessment
- Sensitive data handling
- Dependency security
- Least privilege principle

#### Architecture & Design
- Architectural fit
- Modularity and reusability
- Separation of concerns
- Dependency management
- Future modification impact

#### Documentation & Maintainability
- Code commenting
- Self-documenting code
- API documentation
- Long-term understandability
- TODO items

### 5. Additional Checks

Perform final verification:
- Remove debug statements (console.log, IO.inspect)
- Verify necessary files only
- Assess PR size and reviewability
- Check database migrations
- Validate configuration changes

### 6. Generate Actionable Feedback

Structure feedback with:
- Specific file names and line numbers
- Clear categorization (🚨 ⚠️ 💡 ✅)
- Actionable recommendations
- Focus on meaningful issues over nitpicks
- Consider codebase consistency

## Success Criteria

- All review agents executed successfully
- Findings synthesized comprehensively
- Clear categorization of issues
- Actionable feedback provided
- Planning document verification complete
- Security vulnerabilities identified
- Test coverage assessed
- Code quality validated

## Review Checklist

### Pre-Merge Requirements

**Must Have:**
- [ ] All blocker issues resolved
- [ ] Tests passing
- [ ] Security vulnerabilities addressed
- [ ] Planning document requirements met
- [ ] Code formatted correctly
- [ ] No debug statements

**Should Have:**
- [ ] Concerns addressed or explained
- [ ] Documentation updated
- [ ] Consistent with codebase patterns
- [ ] Adequate test coverage

**Nice to Have:**
- [ ] Suggestions considered
- [ ] Code optimizations applied
- [ ] Additional documentation
- [ ] Performance improvements

## Notes

- This command coordinates multiple specialized review agents
- Provides comprehensive multi-perspective analysis
- Focuses on actionable feedback
- Prioritizes blockers and security issues
- Maintains balance between thoroughness and practicality
