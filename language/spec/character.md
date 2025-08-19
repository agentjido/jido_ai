# Sparq Character Specification

## Overview

A character in Sparq represents an autonomous agent that can participate in conversations and execute planned behaviors. The specification follows Elixir's syntax conventions for clarity and consistency.

## Core Syntax

Characters are defined using a module-based approach with required attributes:

```sparq
character TechnicalGuide do
  @name "Technical Support Guide"
  @goal "Help users learn the system effectively"
  @backstory "An experienced guide focused on user success"
  
  # Optional advanced fields
  @expertise ["troubleshooting", "explaining"]
  @memory_model :pod_based
  @tools [:documentation_search, :code_analysis]
end
```

## Required Attributes

- `@name`: Human-readable character name
- `@goal`: Primary objective/purpose
- `@backstory`: Character history and context

## Optional Attributes

- `@expertise`: List of skill domains
- `@memory_model`: Memory strategy (`:pod_based`, `:episodic`, etc.)
- `@tools`: List of available tool modules
- `@personality`: Character traits and behaviors
- `@voice`: Tone and speaking style

## Internal Data Structure

The character definition generates this runtime structure:

```sparq
%Character{
  name: String.t(),
  goal: String.t(),
  backstory: String.t(),
  expertise: [String.t()],
  memory_model: atom(),
  tools: [atom()],
  personality: map(),
  voice: map(),
  id: UUID.t()
}
```

## Example Usage

Here's a complete example of a character definition:

```sparq
character CustomerSupport do
  @name "Help Desk Agent"
  @goal "Provide timely and accurate support to users"
  @backstory "A knowledgeable support specialist with years of experience"
  
  @expertise ["technical_support", "problem_solving", "customer_service"]
  @memory_model :pod_based
  @tools [:ticket_system, :knowledge_base, :diagnostic_tools]
  
  @personality %{
    patience: :high,
    formality: :professional,
    empathy: :strong
  }
  
  @voice %{
    tone: :helpful,
    style: :clear_and_concise,
    language_level: :technical_but_accessible
  }
end
```

## Best Practices

1. Character Design
   - Give each character a clear, focused purpose
   - Define realistic expertise domains
   - Choose appropriate tools for their role
   - Maintain consistent personality traits

2. Memory Configuration
   - Select memory model based on character needs
   - Consider interaction history requirements
   - Balance between persistence and forgetting

3. Tool Access
   - Only provide tools that match expertise
   - Ensure tools support character goals
   - Consider tool interactions in flows