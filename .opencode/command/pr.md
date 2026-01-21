---
name: pr
description: Create a pull request on GitHub for the current branch
agents:
  - documentation-reviewer
  - factual-reviewer
---

# Pull Request Creation

Creates a pull request on GitHub for the current branch against the main branch.

## Workflow

### 1. Verify Branch Status

Check current branch and ensure it's ready for PR:

```bash
# Get current branch
git branch --show-current

# Check for uncommitted changes
git status

# Verify branch is up to date
git fetch origin
git log origin/main..HEAD --oneline
```

### 2. Gather Context

Identify the work completed:

```bash
# Review commits on this branch
git log main..HEAD --oneline

# Check diff summary
git diff main --stat
```

Locate planning document:
- Feature branches → `notes/features/<feature_name>.md`
- Fix branches → `notes/fixes/<fix_name>.md`
- Task branches → `notes/tasks/<task_name>.md`

### 3. Prepare PR Information

Extract key information from planning document:
- Problem statement
- Solution overview
- Implementation summary
- Testing completed
- Success criteria met

### 4. Generate PR Description

Create a comprehensive PR description:

```markdown
## Summary

[Brief description of what this PR accomplishes]

## Problem

[What issue or need this PR addresses]

## Solution

[How the implementation solves the problem]

## Changes

- [Key change 1]
- [Key change 2]
- [Key change 3]

## Testing

- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing completed
- [ ] All tests passing

## Checklist

- [ ] Code follows project conventions
- [ ] Documentation updated
- [ ] No debug statements left
- [ ] Security considerations addressed
- [ ] Performance impact considered

## Screenshots/Examples

[If applicable, add screenshots or usage examples]

## Related Issues

[Reference any related issues or tickets]
```

### 5. Create Pull Request

Using GitHub CLI (if available):

```bash
# Create PR with title and body
gh pr create \
  --title "[Type]: Brief description" \
  --body "[PR description from above]" \
  --base main \
  --draft false
```

Or provide manual instructions:

```markdown
## Manual PR Creation

1. Push branch to remote:
   ```bash
   git push origin [branch-name]
   ```

2. Navigate to GitHub repository

3. Click "Compare & pull request" for your branch

4. Set PR title:
   - For features: "feat: [description]"
   - For fixes: "fix: [description]"
   - For tasks: "chore: [description]"

5. Paste PR description (see above)

6. Select reviewers if applicable

7. Add labels if applicable

8. Create pull request
```

### 6. Verify PR Creation

Confirm PR was created successfully:

```bash
# If using GitHub CLI
gh pr view

# Or provide the PR URL for manual verification
echo "PR created: https://github.com/[owner]/[repo]/pull/[number]"
```

## PR Title Conventions

Follow conventional commit format:

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only
- `style:` Code style changes
- `refactor:` Code refactoring
- `test:` Test additions/changes
- `chore:` Maintenance tasks

## PR Description Guidelines

### Do Include

- Clear problem statement
- Solution approach
- List of changes
- Testing performed
- Breaking changes (if any)
- Migration instructions (if needed)

### Don't Include

- References to AI assistants
- Internal implementation details
- Unnecessary technical jargon
- Personal opinions
- Unrelated changes

## Success Criteria

- Branch has commits to merge
- All changes committed and pushed
- PR title follows conventions
- PR description is comprehensive
- No references to AI assistants
- Testing information included
- Related issues referenced

## Error Handling

### No Commits to Merge

```markdown
❌ No commits to merge

Current branch has no new commits compared to main.
Make changes and commit them before creating a PR.
```

### Uncommitted Changes

```markdown
⚠️ Uncommitted changes detected

Please commit or stash changes before creating PR:
```bash
git add .
git commit -m "commit message"
```
```

### Not on Feature Branch

```markdown
⚠️ On main branch

Please create and switch to a feature branch:
```bash
git checkout -b feature/branch-name
```
```

## Notes

- PR descriptions should be professional and clear
- Never mention AI assistants in PR content
- Focus on what was accomplished, not how
- Include enough context for reviewers
- Reference planning documents when helpful
