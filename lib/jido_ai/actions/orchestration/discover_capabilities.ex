defmodule Jido.AI.Actions.Orchestration.DiscoverCapabilities do
  @moduledoc """
  Extract capability descriptors from agent modules.

  This action introspects agent modules to build capability descriptors
  that can be used for intelligent task routing.

  ## Parameters

  * `agent_modules` (required) - List of agent modules to introspect
  * `include_actions` (optional) - Include action capabilities (default: true)
  * `include_skills` (optional) - Include skill capabilities (default: true)

  ## Examples

      {:ok, result} = Jido.Exec.run(DiscoverCapabilities, %{
        agent_modules: [MyApp.DocAgent, MyApp.CodeAgent]
      })

  ## Result

      %{
        capabilities: [
          %{
            module: MyApp.DocAgent,
            name: "doc_agent",
            description: "Document analysis agent",
            capabilities: ["pdf_parsing", "summarization"],
            actions: ["analyze", "summarize"],
            skills: ["llm", "planning"]
          },
          ...
        ]
      }
  """

  use Jido.Action,
    name: "discover_capabilities",
    description: "Extract capability descriptors from agent modules",
    category: "orchestration",
    tags: ["orchestration", "discovery", "routing"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        agent_modules: Zoi.list(Zoi.any(), description: "List of agent modules to introspect"),
        include_actions: Zoi.boolean(description: "Include action names") |> Zoi.default(true),
        include_skills: Zoi.boolean(description: "Include skill names") |> Zoi.default(true)
      })

  @impl Jido.Action
  def run(params, _context) do
    capabilities =
      params.agent_modules
      |> Enum.map(&extract_capabilities(&1, params))
      |> Enum.reject(&is_nil/1)

    {:ok, %{capabilities: capabilities}}
  end

  defp extract_capabilities(module, params) do
    if Code.ensure_loaded?(module) do
      base = %{
        module: module,
        name: extract_name(module),
        description: extract_description(module)
      }

      base
      |> maybe_add_actions(module, params[:include_actions])
      |> maybe_add_skills(module, params[:include_skills])
      |> add_declared_capabilities(module)
    end
  end

  defp extract_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  defp extract_description(module) do
    if function_exported?(module, :__agent_config__, 0) do
      config = module.__agent_config__()
      config[:description] || "No description"
    else
      "No description"
    end
  end

  defp maybe_add_actions(base, module, true) do
    actions =
      if function_exported?(module, :actions, 0) do
        module.actions()
        |> Enum.map(fn {name, _mod} -> to_string(name) end)
      else
        []
      end

    Map.put(base, :actions, actions)
  end

  defp maybe_add_actions(base, _module, _), do: base

  defp maybe_add_skills(base, module, true) do
    skills =
      if function_exported?(module, :skills, 0) do
        module.skills()
        |> Enum.map(fn
          {skill_mod, _opts} -> extract_name(skill_mod)
          skill_mod when is_atom(skill_mod) -> extract_name(skill_mod)
        end)
      else
        []
      end

    Map.put(base, :skills, skills)
  end

  defp maybe_add_skills(base, _module, _), do: base

  defp add_declared_capabilities(base, module) do
    capabilities =
      if function_exported?(module, :capabilities, 0) do
        module.capabilities()
      else
        []
      end

    Map.put(base, :capabilities, capabilities)
  end
end
