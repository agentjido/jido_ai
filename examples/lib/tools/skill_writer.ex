defmodule Jido.AI.Examples.Tools.ValidateSkillName do
  @moduledoc "Validates a proposed skill name against agentskills.io rules."

  use Jido.Action,
    schema: Zoi.object(%{name: Zoi.string(description: "The proposed skill name to validate")}),
    name: "validate_skill_name",
    description: "Validates a skill name matches the pattern: lowercase alphanumeric with hyphens, max 64 chars."

  @name_regex ~r/^[a-z0-9]+(-[a-z0-9]+)*$/
  @max_length 64

  @impl true
  def run(params, _context) do
    name = params.name

    cond do
      String.length(name) == 0 ->
        {:ok, %{valid: false, name: name, error: "Name cannot be empty"}}

      String.length(name) > @max_length ->
        {:ok, %{valid: false, name: name, error: "Name exceeds #{@max_length} characters"}}

      not Regex.match?(@name_regex, name) ->
        {:ok,
         %{
           valid: false,
           name: name,
           error: "Name must be lowercase alphanumeric with hyphens (e.g., 'my-skill-name')"
         }}

      true ->
        {:ok, %{valid: true, name: name, suggestion: nil}}
    end
  end
end

defmodule Jido.AI.Examples.Tools.WriteModuleSkill do
  @moduledoc "Generates Elixir module code for a Jido.AI.Skill."

  use Jido.Action,
    schema:
      Zoi.object(%{
        module_name: Zoi.string(description: "Full module name, e.g., 'MyApp.Skills.CodeReview'"),
        name: Zoi.string(description: "Skill name (lowercase-hyphenated)"),
        description: Zoi.string(description: "Skill description (1-1024 chars)"),
        license: Zoi.string(description: "License identifier, e.g., 'MIT'") |> Zoi.optional(),
        allowed_tools: Zoi.list(Zoi.string([]), description: "List of allowed tool names") |> Zoi.optional(),
        actions: Zoi.list(Zoi.string([]), description: "List of action module names") |> Zoi.optional(),
        tags: Zoi.list(Zoi.string([]), description: "List of tags") |> Zoi.optional(),
        body: Zoi.string(description: "Skill body content (markdown)")
      }),
    name: "write_module_skill",
    description: "Generates Elixir module source code for a skill using `use Jido.AI.Skill`."

  @impl true
  def run(params, _context) do
    module_name = params.module_name
    name = params.name
    description = params.description
    license = Map.get(params, :license)
    allowed_tools = Map.get(params, :allowed_tools, [])
    actions = Map.get(params, :actions, [])
    tags = Map.get(params, :tags, [])
    body = params.body

    code = generate_module_code(module_name, name, description, license, allowed_tools, actions, tags, body)

    {:ok, %{format: "elixir_module", module_name: module_name, code: code}}
  end

  defp generate_module_code(module_name, name, description, license, allowed_tools, actions, tags, body) do
    opts = [
      ~s(name: "#{name}"),
      ~s(description: "#{escape_string(description)}")
    ]

    opts = if license, do: opts ++ [~s(license: "#{license}")], else: opts
    opts = if allowed_tools != [], do: opts ++ [format_allowed_tools(allowed_tools)], else: opts
    opts = if actions != [], do: opts ++ [format_actions(actions)], else: opts
    opts = if tags != [], do: opts ++ [format_tags(tags)], else: opts
    opts = opts ++ [format_body(body)]

    opts_str = Enum.join(opts, ",\n    ")

    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      #{description}
      \"\"\"

      use Jido.AI.Skill,
        #{opts_str}
    end
    """
  end

  defp escape_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", " ")
  end

  defp format_allowed_tools(tools) do
    tools_str = Enum.join(tools, " ")
    "allowed_tools: ~w(#{tools_str})"
  end

  defp format_actions(actions) do
    actions_str = Enum.map_join(actions, ",\n", &"      #{&1}")

    "actions: [\n#{actions_str}\n    ]"
  end

  defp format_tags(tags) do
    tags_str = Enum.map_join(tags, ", ", &~s("#{&1}"))
    "tags: [#{tags_str}]"
  end

  defp format_body(body) do
    indented_body = String.replace(body, "\n", "\n    ")
    ~s|body: """\n    #{indented_body}\n    """|
  end
end

defmodule Jido.AI.Examples.Tools.WriteFileSkill do
  @moduledoc "Generates a SKILL.md file with YAML frontmatter."

  use Jido.Action,
    schema:
      Zoi.object(%{
        name: Zoi.string(description: "Skill name (lowercase-hyphenated)"),
        description: Zoi.string(description: "Skill description (1-1024 chars)"),
        license: Zoi.string(description: "License identifier, e.g., 'MIT'") |> Zoi.optional(),
        allowed_tools: Zoi.list(Zoi.string([]), description: "List of allowed tool names") |> Zoi.optional(),
        tags: Zoi.list(Zoi.string([]), description: "List of tags") |> Zoi.optional(),
        metadata: Zoi.map(description: "Additional metadata as key-value pairs") |> Zoi.optional(),
        body: Zoi.string(description: "Skill body content (markdown)")
      }),
    name: "write_file_skill",
    description: "Generates a SKILL.md file content with YAML frontmatter and markdown body."

  @impl true
  def run(params, _context) do
    name = params.name
    description = params.description
    license = Map.get(params, :license)
    allowed_tools = Map.get(params, :allowed_tools, [])
    tags = Map.get(params, :tags, [])
    metadata = Map.get(params, :metadata, %{})
    body = params.body

    content = generate_skill_md(name, description, license, allowed_tools, tags, metadata, body)
    suggested_path = Jido.AI.Examples.Paths.examples_relative_repo_path("priv/skills/#{name}/SKILL.md")

    {:ok, %{format: "skill_md", suggested_path: suggested_path, content: content}}
  end

  defp generate_skill_md(name, description, license, allowed_tools, tags, metadata, body) do
    frontmatter_lines = [
      "---",
      "name: #{name}",
      "description: #{description}"
    ]

    frontmatter_lines =
      if license do
        frontmatter_lines ++ ["license: #{license}"]
      else
        frontmatter_lines
      end

    frontmatter_lines =
      if allowed_tools != [] do
        frontmatter_lines ++ ["allowed-tools: #{Enum.join(allowed_tools, " ")}"]
      else
        frontmatter_lines
      end

    frontmatter_lines =
      if tags != [] do
        tag_lines = Enum.map(tags, &"  - #{&1}")
        frontmatter_lines ++ ["tags:"] ++ tag_lines
      else
        frontmatter_lines
      end

    frontmatter_lines =
      if metadata != %{} do
        metadata_lines =
          Enum.flat_map(metadata, fn {k, v} ->
            ["  #{k}: #{inspect(v)}"]
          end)

        frontmatter_lines ++ ["metadata:"] ++ metadata_lines
      else
        frontmatter_lines
      end

    frontmatter_lines = frontmatter_lines ++ ["---", ""]

    Enum.join(frontmatter_lines, "\n") <> "\n" <> body
  end
end
