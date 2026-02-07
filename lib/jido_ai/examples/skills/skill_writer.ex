defmodule Jido.AI.Examples.Skills.SkillWriter do
  @moduledoc """
  Meta-skill for creating new Jido.AI.Skill definitions.

  This skill helps users create both:
  - Module-based skills (Elixir code with `use Jido.AI.Skill`)
  - File-based skills (YAML frontmatter SKILL.md files)

  ## Usage

      # Add to an agent's skills list
      skills: [Jido.AI.Examples.Skills.SkillWriter]

      # Ask the agent to create a skill
      "Create a skill for summarizing documents"
      "Write a SKILL.md for a code review skill"
  """

  use Jido.AI.Skill,
    name: "skill-writer",
    description: "Creates new Jido.AI.Skill definitions in either module or YAML format.",
    license: "Apache-2.0",
    allowed_tools: ~w(write_module_skill write_file_skill validate_skill_name),
    actions: [
      Jido.AI.Examples.Tools.WriteModuleSkill,
      Jido.AI.Examples.Tools.WriteFileSkill,
      Jido.AI.Examples.Tools.ValidateSkillName
    ],
    tags: ["meta", "skill-creation", "code-generation"],
    body: """
    # Skill Writer

    ## Purpose
    Use this skill when users want to create new skills for Jido agents.
    You can generate either Elixir module code or YAML SKILL.md files.

    ## Skill Naming Rules
    - Names must be lowercase alphanumeric with hyphens only
    - Pattern: `^[a-z0-9]+(-[a-z0-9]+)*$`
    - Max 64 characters
    - Examples: `code-review`, `weather-advisor`, `data-processor`

    ## Format Choice

    ### Use Module Format When:
    - The skill needs to reference specific Elixir action modules
    - Compile-time validation is important
    - The skill is part of the application codebase

    ### Use File Format When:
    - The skill is user-configurable or loaded at runtime
    - Non-developers need to edit the skill
    - The skill should be portable across projects

    ## Workflow

    1. **Gather Requirements**
       - What is the skill's purpose?
       - What tools/actions should it use?
       - What workflow should it follow?

    2. **Validate the Name**
       - Use `validate_skill_name` to check the proposed name

    3. **Generate the Skill**
       - Use `write_module_skill` for Elixir module format
       - Use `write_file_skill` for YAML SKILL.md format

    4. **Review Output**
       - Present the generated code/file to the user
       - Explain how to use it

    ## Required Fields
    - `name` - Unique skill identifier (validated)
    - `description` - 1-1024 chars explaining when to use the skill

    ## Optional Fields
    - `license` - e.g., "MIT", "Apache-2.0"
    - `allowed_tools` - Space-delimited or list of tool names
    - `tags` - List of categorization tags
    - `metadata` - Arbitrary key-value pairs

    ## Body Structure (Best Practices)

    A good skill body includes:
    1. **Purpose** - When to activate this skill
    2. **Available Operations** - Tools the skill can use
    3. **Workflow** - Step-by-step process
    4. **Examples** - Concrete usage examples
    5. **Best Practices** - Tips for effective use

    ## Example Module Output

    ```elixir
    defmodule MyApp.Skills.DocumentSummarizer do
      use Jido.AI.Skill,
        name: "document-summarizer",
        description: "Summarizes long documents into key points.",
        license: "MIT",
        allowed_tools: ~w(extract_text summarize_chunk combine_summaries),
        actions: [
          MyApp.Actions.ExtractText,
          MyApp.Actions.SummarizeChunk,
          MyApp.Actions.CombineSummaries
        ],
        body: \"""
        # Document Summarizer

        ## Purpose
        Use when users need to condense long documents...
        \"""
    end
    ```

    ## Example SKILL.md Output

    ```yaml
    ---
    name: document-summarizer
    description: Summarizes long documents into key points.
    license: MIT
    allowed-tools: extract_text summarize_chunk combine_summaries
    tags:
      - nlp
      - summarization
    ---

    # Document Summarizer

    ## Purpose
    Use when users need to condense long documents...
    ```
    """
end
