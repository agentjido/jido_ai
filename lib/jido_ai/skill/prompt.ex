defmodule Jido.AI.Skill.Prompt do
  @moduledoc """
  Renders skills into prompt text for agent system prompts.

  Provides utilities to format skill manifests and bodies into
  structured text that can be prepended/appended to agent prompts.
  """

  alias Jido.AI.Skill
  alias Jido.AI.Skill.{Registry, Spec}

  @default_index_header "## Skills"
  @default_load_instruction """
  When the user's request matches a skill above, call `load_skill` with the skill
  name to retrieve the full instructions, then follow them step by step.
  """

  @doc """
  Renders a list of skills into a formatted prompt section.

  ## Options

  - `:include_body` - Include skill body content (default: true)
  - `:header` - Custom header text (default: "You have access to the following skills:")

  ## Example

      skills = [MyApp.Skills.Calculator, "code-review"]
      Skill.Prompt.render(skills)
      # => "You have access to the following skills:\\n\\n## calculator\\n..."
  """
  @spec render([module() | Spec.t() | String.t()], keyword()) :: String.t()
  def render(skills, opts \\ []) do
    include_body = Keyword.get(opts, :include_body, true)
    header = Keyword.get(opts, :header, "You have access to the following skills:")

    skill_sections =
      skills
      |> Enum.map(&resolve_skill/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join("\n\n", &format_skill(&1, include_body))

    if skill_sections == "" do
      ""
    else
      "#{header}\n\n#{skill_sections}"
    end
  end

  @doc """
  Renders a compact, model-facing skill index.

  Unlike `render/2`, this function intentionally omits skill bodies so prompts
  can advertise available skills without loading their full instructions. Pair
  the rendered index with `Jido.AI.Actions.Skill.LoadSkill` so a model can load
  the selected skill body on demand.

  ## Options

  - `:tags` - String, atom, or list of tags used to filter skills.
  - `:tag_match` - `:any` (default) or `:all` when multiple tags are provided.
  - `:header` - Header text (default: `"## Skills"`). Set to `false` or `nil`
    to omit.
  - `:load_instruction` - Instruction appended after the index. Set to `false`
    or `nil` to omit.
  - `:include_allowed_tools` - Append allowed tool names to each entry.
  """
  @spec render_index([module() | Spec.t() | String.t()], keyword()) :: String.t()
  def render_index(skills, opts \\ []) do
    tag_filter = normalize_tags(Keyword.get(opts, :tags, []))
    tag_match = Keyword.get(opts, :tag_match, :any)
    include_allowed_tools = Keyword.get(opts, :include_allowed_tools, false)

    entries =
      skills
      |> Enum.map(&resolve_skill/1)
      |> Enum.reject(&is_nil/1)
      |> filter_by_tags(tag_filter, tag_match)
      |> Enum.map_join("\n", &format_index_entry(&1, include_allowed_tools))

    if entries == "" do
      ""
    else
      opts
      |> index_parts(entries)
      |> Enum.join("\n\n")
    end
  end

  @doc """
  Renders a compact index for skills currently registered in the runtime registry.

  This is the common entry point for lazy skill loading: register runtime skills,
  render a filtered index into the agent system prompt, and expose the
  `load_skill` action so the agent can retrieve the full body only when needed.
  """
  @spec render_registry_index(keyword()) :: String.t()
  def render_registry_index(opts \\ []) do
    Registry.all()
    |> Enum.sort_by(& &1.name)
    |> render_index(opts)
  end

  @doc """
  Renders a single skill into formatted prompt text.
  """
  @spec render_one(module() | Spec.t() | String.t(), keyword()) :: String.t()
  def render_one(skill, opts \\ []) do
    include_body = Keyword.get(opts, :include_body, true)

    case resolve_skill(skill) do
      nil -> ""
      spec -> format_skill(spec, include_body)
    end
  end

  @doc """
  Collects all allowed tools from a list of skills.

  Returns the union of all `allowed_tools` from the given skills.
  """
  @spec collect_allowed_tools([module() | Spec.t() | String.t()]) :: [String.t()]
  def collect_allowed_tools(skills) do
    skills
    |> Enum.map(&resolve_skill/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(& &1.allowed_tools)
    |> Enum.uniq()
  end

  @doc """
  Filters a list of tool modules by the allowed tools from skills.

  Returns only the tools whose names match the union of `allowed_tools`
  from the given skills. If no skills specify allowed_tools, returns all tools.
  """
  @spec filter_tools([module()], [module() | Spec.t() | String.t()]) :: [module()]
  def filter_tools(tools, skills) do
    allowed = collect_allowed_tools(skills)

    if allowed == [] do
      tools
    else
      allowed_set = MapSet.new(allowed)

      Enum.filter(tools, fn tool ->
        tool_name = get_tool_name(tool)
        MapSet.member?(allowed_set, tool_name)
      end)
    end
  end

  # Private functions

  defp resolve_skill(skill) do
    case Skill.resolve(skill) do
      {:ok, spec} -> spec
      {:error, _} -> nil
    end
  end

  defp format_skill(%{__struct__: Spec} = spec, include_body) do
    tools_line =
      case spec.allowed_tools do
        [] -> ""
        tools -> "\nAllowed tools: #{Enum.join(tools, ", ")}"
      end

    body_section =
      if include_body do
        body = Skill.body(spec)
        if body == "", do: "", else: "\n\n#{body}"
      else
        ""
      end

    """
    ## #{spec.name}
    #{spec.description}#{tools_line}#{body_section}
    """
    |> String.trim_trailing()
  end

  defp index_parts(opts, entries) do
    header = Keyword.get(opts, :header, @default_index_header)
    load_instruction = Keyword.get(opts, :load_instruction, @default_load_instruction)

    [header, entries, load_instruction]
    |> Enum.reject(&(&1 in [nil, false, ""]))
    |> Enum.map(&String.trim/1)
  end

  defp format_index_entry(%Spec{} = spec, include_allowed_tools) do
    tools =
      case {include_allowed_tools, spec.allowed_tools} do
        {true, [_ | _] = allowed_tools} -> " (tools: #{Enum.join(allowed_tools, ", ")})"
        _ -> ""
      end

    description =
      spec.description
      |> String.trim()
      |> String.replace("\n", "\n  ")

    "* **#{spec.name}**: #{description}#{tools}"
  end

  defp filter_by_tags(specs, [], _tag_match), do: specs

  defp filter_by_tags(specs, tags, :all) do
    required = MapSet.new(tags)

    Enum.filter(specs, fn %Spec{tags: spec_tags} ->
      spec_set = spec_tags |> normalize_tags() |> MapSet.new()
      MapSet.subset?(required, spec_set)
    end)
  end

  defp filter_by_tags(specs, tags, _tag_match) do
    wanted = MapSet.new(tags)

    Enum.filter(specs, fn %Spec{tags: spec_tags} ->
      spec_tags
      |> normalize_tags()
      |> Enum.any?(&MapSet.member?(wanted, &1))
    end)
  end

  defp normalize_tags(nil), do: []
  defp normalize_tags(tag) when is_atom(tag), do: [Atom.to_string(tag)]
  defp normalize_tags(tag) when is_binary(tag), do: [tag]

  defp normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.flat_map(&normalize_tags/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_tags(_), do: []

  defp get_tool_name(tool) when is_atom(tool) do
    if function_exported?(tool, :name, 0) do
      tool.name()
    else
      tool
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
    end
  end
end
