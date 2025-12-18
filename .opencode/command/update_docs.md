---
description: Systematically update all project documentation to reflect the current state of the code
tools:
  - bash
  - read
  - write
  - edit
  - grep
  - glob
agents:
  - documentation-expert
  - documentation-reviewer
---

# Update Documentation

## Context Analysis

First, analyze the current state of the project to understand what documentation needs updating:

```bash
# Check current branch
git branch --show-current

# Review recent commits
git log --oneline -10

# List modified files
git diff --name-only HEAD~5..HEAD
```

## Documentation Discovery

Locate all existing documentation files:

```bash
# Find all markdown documentation
find . -name "*.md" -type f | grep -v node_modules | grep -v .git | sort
```

Review the following documentation locations:
- `README.md` - Project overview
- `PROJECT.md` - Detailed project information  
- `CONTRIBUTING.md` - Development guidelines
- `CHANGELOG.md` - Version history
- `docs/` - Technical documentation
- `notes/features/` - Feature documentation
- `notes/fixes/` - Fix documentation
- `notes/tasks/` - Task documentation

## Documentation Expert Analysis

Invoke the documentation-expert agent to analyze and update documentation:

<agent>documentation-expert</agent>

The documentation-expert should:
1. Analyze code changes against existing documentation
2. Identify gaps in documentation coverage
3. Update existing docs to reflect current implementation
4. Create new sections for undocumented features
5. Apply industry-standard methodologies (Docs as Code, DITA, etc.)
6. Ensure consistency with style guides
7. Implement accessibility best practices

## Documentation Updates

Based on the expert's analysis, update the following documentation categories:

### Project Documentation

Update core project files:
- `README.md` - Installation, quick start, basic usage
- `PROJECT.md` - Architecture, technology stack, development
- `CONTRIBUTING.md` - Code standards, PR process, testing
- `CHANGELOG.md` - Recent changes, version history

### Feature Documentation  

For each feature in `notes/features/`:
- Update implementation status
- Mark completed steps with ✅
- Document any deviations from plan
- Add current status section

### Technical Documentation

Update or create:
- API documentation with endpoints and examples
- Configuration guides with environment variables
- Architecture diagrams and decisions
- Troubleshooting guides

### Code Documentation

Ensure code has:
- Updated inline comments
- Function/module documentation
- Type definitions
- Usage examples

## Quality Review

Invoke the documentation-reviewer agent to validate all updates:

<agent>documentation-reviewer</agent>

The reviewer should verify:
1. **Technical Accuracy** - Examples work, APIs match implementation
2. **Completeness** - All features documented, prerequisites stated
3. **Style Compliance** - Consistent terminology and formatting
4. **Readability** - Clear structure, appropriate level
5. **Accessibility** - WCAG compliance, alt text, clear headings

## Commit Changes

After review approval, commit the documentation updates:

```bash
# Stage documentation changes
git add -A docs/ notes/ *.md

# Create descriptive commit
git commit -m "docs: comprehensive documentation update

- Updated README with latest features
- Synchronized API documentation
- Updated feature documentation status
- Added missing configuration docs
- Fixed outdated examples"
```

## Success Criteria

Documentation update is complete when:
- [ ] All code changes have corresponding documentation
- [ ] All examples are tested and working
- [ ] Style guide compliance verified
- [ ] Accessibility standards met
- [ ] Quality review passed
- [ ] Changes committed with clear message

## Integration

This command should be run:
- After feature implementation completion
- After bug fix implementation  
- Before creating pull requests
- As part of release preparation
- Whenever documentation drift is suspected

## Notes

- Documentation-expert handles the actual updates following best practices
- Documentation-reviewer ensures quality standards are met
- The workflow ensures systematic coverage of all documentation
- Git integration tracks all documentation changes properly
