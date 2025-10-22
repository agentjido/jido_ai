---
name: reflect
description: Reflect on recent changes and update project documentation with learnings and decisions
agents:
  - documentation-expert
  - consistency-reviewer
  - architecture-agent
---

# Reflect - Session Retrospection and Documentation

Reflects on recent changes made to the codebase and updates project documentation with learnings, decisions, and current state.

## Workflow

### 1. Analyze Recent Changes

Review recent work to identify what has changed:

```bash
# Check recent commits
git log --oneline -20

# Review changed files
git diff main --stat

# Examine specific changes
git diff main --name-only | head -20
```

Categorize changes by type:
- **Architecture Changes**: Structural modifications, new patterns
- **Design Changes**: API design, module organization
- **Code Changes**: Implementation details, refactoring
- **Test Changes**: New tests, test improvements
- **Documentation Changes**: README, guides, inline docs

### 2. Session History Analysis

Review the current session to understand:
- Features implemented
- Problems solved
- Decisions made
- Patterns established
- Lessons learned

Create a summary of findings:

```markdown
## Session Reflection

### What We Built
- [Feature/fix descriptions]
- [Key functionality added]

### Architecture Decisions
- [Structural choices made]
- [Pattern selections]
- [Module organization]

### Technical Learnings
- [Framework insights]
- [Language patterns discovered]
- [Tool usage lessons]

### Challenges Overcome
- [Problems encountered]
- [Solutions applied]

### What Worked Well
- [Successful approaches]
- [Effective patterns]

### Areas for Improvement
- [Technical debt identified]
- [Future refactoring needs]
```

### 3. Update CLAUDE.md

Update the AI assistant instructions with project-specific learnings:

**Invoke `documentation-expert` to:**
1. Read current CLAUDE.md
2. Identify sections needing updates
3. Add new learnings while avoiding duplication
4. Ensure consistency and coherence
5. Remove outdated or unnecessary content

**Key sections to update:**
- Language/framework patterns discovered
- Project-specific conventions
- Architectural decisions
- Testing approaches
- Common pitfalls to avoid

**Quality checks:**
- [ ] No duplicate information
- [ ] High coherence throughout
- [ ] Consistent with project reality
- [ ] Critical review - remove fluff
- [ ] Actionable guidance

### 4. Update PROJECT.md

Update the project documentation with new features and decisions:

**Invoke `documentation-expert` to:**
1. Read current PROJECT.md
2. Add new features implemented
3. Document architectural decisions
4. Update design patterns section
5. Maintain document quality

**Sections to update:**
- Features list
- Architecture overview
- Technology decisions
- API documentation
- Configuration details
- Development workflow

**Quality checks:**
- [ ] Accurate feature descriptions
- [ ] Current architecture representation
- [ ] No redundant information
- [ ] Clear and concise
- [ ] Properly structured

### 5. Update Planning Documents

Review and update planning documents in the notes folder:

```bash
# List planning documents
ls -la notes/features/
ls -la notes/fixes/
ls -la notes/tasks/
```

For each relevant planning document:
1. Update implementation status
2. Mark completed items
3. Add lessons learned
4. Note any deviations from plan
5. Remove outdated information

**Planning document updates:**

```markdown
## Implementation Status: ✅ COMPLETED

### Final Implementation Summary
- [What was actually built]
- [Deviations from original plan]
- [Lessons learned]

### Retrospective Notes
- **What went well**: [Successes]
- **Challenges**: [Difficulties encountered]
- **Would do differently**: [Improvements for next time]
```

### 6. Consistency Review

**Invoke `consistency-reviewer` to:**
- Verify documentation consistency
- Check for contradictions
- Ensure alignment across all docs
- Validate information accuracy

### 7. Create Reflection Summary

Generate a final reflection report:

```markdown
# Reflection Summary - [Date]

## Changes Made
### Architecture
- [List of architectural changes]

### Code
- [Significant code changes]

### Tests
- [Test improvements/additions]

### Documentation
- [Documentation updates]

## Key Learnings
- [Important discoveries]
- [Pattern insights]
- [Tool knowledge]

## Documentation Updated
- ✅ CLAUDE.md - Added [specific sections]
- ✅ PROJECT.md - Updated [specific sections]
- ✅ Planning docs - Completed [which documents]

## Action Items
- [Future improvements identified]
- [Technical debt to address]
- [Documentation gaps to fill]
```

### 8. Commit Documentation Updates

```bash
# Stage documentation changes
git add CLAUDE.md PROJECT.md
git add notes/

# Commit with descriptive message
git commit -m "docs: reflect on session and update project documentation

- Updated CLAUDE.md with new learnings
- Updated PROJECT.md with feature documentation
- Completed planning document retrospectives
- Added architectural decisions"
```

## Success Criteria

- Recent changes analyzed comprehensively
- All relevant documentation updated
- No duplicate information added
- High coherence maintained
- Unnecessary content removed
- Learnings captured effectively
- Planning documents current
- Consistency verified

## Quality Standards

### Documentation Coherence
- Information flows logically
- No contradictions
- Clear structure
- Concise content

### Critical Review
- Remove redundant content
- Eliminate outdated information
- Focus on actionable insights
- Maintain relevance

### Consistency
- Terminology uniform across docs
- Patterns documented consistently
- Decisions aligned
- Information synchronized

## Notes

- This command ensures knowledge persistence across sessions
- Maintains living documentation that evolves with the project
- Captures learnings for future development
- Provides regular documentation maintenance
- Enables knowledge transfer and onboarding
