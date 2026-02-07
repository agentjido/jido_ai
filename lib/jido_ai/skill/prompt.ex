defmodule Jido.AI.Skill.Prompt do
  @moduledoc """
  Renders skills into prompt text for agent system prompts.

  Provides utilities to format skill manifests and bodies into
  structured text that can be prepended/appended to agent prompts.
  """

  alias Jido.AI.Skill
  alias Jido.AI.Skill.Spec

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
