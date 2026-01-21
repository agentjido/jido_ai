---
name: document
description: Create new documentation or comprehensively document existing features using industry-standard methodologies
agents:
  - documentation-expert
  - documentation-reviewer
---

# Document - Create Comprehensive Documentation

Creates new documentation or documents existing features using industry-standard methodologies and specialized documentation agents.

## Workflow

### 1. Identify Documentation Needs

Analyze what needs to be documented:

**Target Analysis:**
- What needs to be documented?
- Who is the target audience?
- What type of documentation is needed?
- What level of detail is required?

**Documentation Types:**
- **API Reference** - OpenAPI/REST/GraphQL endpoints
- **Architecture Documentation** - C4 Model, ADRs
- **User Guides** - Tutorials, how-tos
- **Developer Documentation** - Setup, contributing
- **Troubleshooting Guides** - Common issues and solutions

### 2. Documentation Creation

Invoke `documentation-expert` to create documentation:

The expert will:
- Select appropriate methodology (Docs as Code, DITA, minimalism)
- Apply relevant style guide (Google Developer Documentation Style)
- Structure content with progressive disclosure
- Include necessary sections and examples
- Ensure accessibility compliance (WCAG)

### 3. Content Development

The `documentation-expert` develops content:

1. **Create structure** based on documentation type
2. **Write content** following methodology
3. **Add examples** and code samples
4. **Include visuals** where helpful
5. **Implement navigation** and cross-references

### 4. Apply Documentation Templates

#### Feature Documentation Template

```markdown
# Feature Name

## Overview
Brief description and value proposition

## Getting Started
Minimal steps to first success

## Core Concepts
Key terms and ideas explained

## Usage Guide

### Basic Usage
Common scenarios with examples

### Advanced Usage
Complex scenarios and edge cases

## API Reference
Detailed parameter documentation

## Configuration
Available options and defaults

## Troubleshooting
Common issues and solutions

## Related Resources
Links to relevant documentation
```

#### API Documentation Template

```markdown
# API Name

## Overview
API purpose and capabilities

## Authentication
How to authenticate requests

## Base URL
`https://api.example.com/v1`

## Endpoints

### GET /resource
Brief description

**Parameters**
- `param1` (required): Description
- `param2` (optional): Description

**Response**
\`\`\`json
{
  "field": "value"
}
\`\`\`

**Error Codes**
- `400`: Bad Request
- `401`: Unauthorized
- `404`: Not Found

## Rate Limiting
Request limits and headers

## Examples
Complete request/response examples
```

#### Architecture Documentation Template

```markdown
# System Architecture

## Overview
High-level system description

## System Context (C4 Level 1)
External systems and users

## Container Diagram (C4 Level 2)
Applications and data stores

## Key Decisions

### ADR-001: [Decision Title]
**Status**: Accepted
**Context**: Why this decision was needed
**Decision**: What was decided
**Consequences**: Impact of decision

## Security Architecture
Authentication and authorization

## Deployment Architecture
Infrastructure and deployment

## Performance Considerations
Scalability and optimization
```

### 5. Quality Assurance

Invoke `documentation-reviewer` to validate:

**Review Checklist:**
- [ ] Technical accuracy verified
- [ ] Completeness checked
- [ ] Style guide compliance confirmed
- [ ] Readability score acceptable (60-70 Flesch)
- [ ] Accessibility standards met (WCAG)
- [ ] Examples tested and working
- [ ] Navigation logical and clear

### 6. Documentation Standards

Apply these standards throughout:

#### Language Guidelines
- Active voice: "The system processes..."
- Present tense: "The API returns..."
- Second person: "You can configure..."
- Plain language (8th-10th grade level)
- Technical terms defined on first use

#### Structure Guidelines
- Clear heading hierarchy (H1 → H2 → H3)
- Short paragraphs (3-5 sentences)
- Bulleted lists for clarity
- Code examples with syntax highlighting
- Visual aids where beneficial

#### Quality Metrics
- **Reading level**: 8th-10th grade
- **Completeness**: All features covered
- **Accuracy**: Technically correct
- **Accessibility**: WCAG compliant
- **Maintainability**: Easy to update

### 7. Integration and Placement

Determine documentation location:

```bash
# API documentation
docs/api/[api-name].md

# Feature documentation
docs/features/[feature-name].md

# Architecture documentation
docs/architecture/[component].md

# User guides
docs/guides/[guide-name].md

# Developer documentation
docs/development/[topic].md
```

Update navigation and indexes:
- Add to table of contents
- Update README links
- Create cross-references
- Add to search index

### 8. Commit Documentation

```bash
# Stage documentation files
git add docs/

# Commit with descriptive message
git commit -m "docs: add [type] documentation for [feature/api/component]

- Created comprehensive [type] documentation
- Includes examples and code samples
- Follows [style guide] standards
- Reviewed for accuracy and completeness"
```

## Usage Examples

### Document a New API

```bash
/document api authentication-service

# Creates:
# - API overview and authentication
# - Endpoint documentation
# - Request/response examples
# - Error codes and rate limiting
```

### Document Existing Feature

```bash
/document feature user-management

# Creates:
# - Feature overview
# - Usage guide with examples
# - Configuration options
# - Troubleshooting section
```

### Create Architecture Documentation

```bash
/document architecture system-overview

# Creates:
# - C4 model diagrams
# - Architecture decision records
# - Security architecture
# - Performance considerations
```

### Create User Guide

```bash
/document guide getting-started

# Creates:
# - Step-by-step tutorial
# - Prerequisites
# - Common tasks
# - FAQ section
```

## Success Criteria

- [ ] Documentation type identified
- [ ] Appropriate template selected
- [ ] Content comprehensive and accurate
- [ ] Examples tested and working
- [ ] Style guide followed
- [ ] Accessibility standards met
- [ ] Quality review passed
- [ ] Documentation integrated properly
- [ ] Navigation updated
- [ ] Changes committed

## Error Handling

### Unclear Documentation Needs

```markdown
⚠️ Documentation scope unclear

Please specify:
- What to document (feature/api/architecture)
- Target audience (users/developers/operators)
- Detail level needed (overview/comprehensive)
```

### Missing Context

```markdown
❌ Cannot document without implementation

Required:
- Feature/API must be implemented
- Code must be accessible
- Functionality must be testable
```

### Quality Issues

```markdown
⚠️ Documentation quality issues detected

Fix required:
- Technical inaccuracies: [count]
- Missing sections: [list]
- Readability issues: [score]
```

## Integration Points

- **After feature implementation** - Document completed features
- **Definition of done** - Include documentation requirement
- **Release process** - Update docs before release
- **Regular reviews** - Schedule documentation audits
- **Continuous improvement** - Iterate based on feedback

## Notes

- This command ensures comprehensive documentation creation
- Follows industry-standard methodologies
- Maintains consistency across documentation
- Enables self-service through clear guides
- Reduces support burden through good documentation
