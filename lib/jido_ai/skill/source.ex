defmodule Jido.AI.Skill.Source do
  @moduledoc "Static skill sources and runtime catalogue preparation for AI profiles."
  alias Jido.AI.{Profile, ToolCatalog}
  alias Jido.AI.Skill.{AgentIntegration, ResourcePolicy, ResourceProvider, Spec}

  @fields [
    :paths,
    :trust,
    :specs,
    :modules,
    :resource_policy,
    :resource_provider,
    :max_depth,
    :max_directories,
    :exclude_directories
  ]

  @doc "Validates a source without reading skill files or invoking host callbacks."
  def new(value) when value in [nil, false, []], do: {:ok, nil}
  def new(true), do: new(%{paths: :default, trust: true})

  def new(value) when is_list(value) do
    cond do
      Keyword.keyword?(value) and length(value) == map_size(Map.new(value)) -> new(Map.new(value))
      Enum.all?(value, &is_binary/1) -> new(%{paths: value, trust: true})
      true -> Profile.error("skills", "Expected unique options or trusted paths")
    end
  end

  def new(value) do
    with {:ok, attrs} <- Profile.fields(value, @fields, "skills"),
         {:ok, specs} <- Profile.traverse(Map.get(attrs, :specs, []), &Spec.validate_runtime/1),
         true <- length(specs) == length(Enum.uniq_by(specs, & &1.name)),
         {:ok, modules} <- Profile.traverse(Map.get(attrs, :modules, []), &skill_module/1),
         paths = Map.get(attrs, :paths, if(specs == [] and modules == [], do: :default, else: [])),
         true <-
           paths == :default or
             (is_list(paths) and Enum.all?(paths, &(is_binary(&1) and &1 != ""))),
         {:ok, trust} <- trust(Map.get(attrs, :trust, false)),
         {:ok, policy} <- ResourcePolicy.new(Map.get(attrs, :resource_policy, %{})),
         {:ok, provider} <- ResourceProvider.validate(Map.get(attrs, :resource_provider)),
         :ok <- limits(attrs),
         :ok <- Jido.Action.validate_static_data(attrs) do
      {:ok,
       attrs
       |> Map.merge(%{
         paths: paths,
         trust: trust,
         specs: specs,
         modules: modules,
         resource_policy: policy,
         resource_provider: provider
       })}
    else
      false -> Profile.error("skills", "Expected valid paths and unique skill names")
      {:error, reason} -> Profile.error("skills", inspect(reason))
    end
  end

  defp limits(attrs) do
    depth = Map.get(attrs, :max_depth, 6)
    directories = Map.get(attrs, :max_directories, 2_000)
    excluded = Map.get(attrs, :exclude_directories, [".git", "node_modules"])

    if is_integer(depth) and depth >= 0 and is_integer(directories) and directories > 0 and
         is_list(excluded) and Enum.all?(excluded, &is_binary/1),
       do: :ok,
       else: Profile.error("skills", "Invalid discovery bounds")
  end

  defp skill_module(module) when is_atom(module) and module != nil do
    with {:module, _} <- Code.ensure_compiled(module),
         true <- function_exported?(module, :manifest, 0),
         do: {:ok, module},
         else: (_ -> Profile.error("skills.modules", "Expected a skill module"))
  end

  defp skill_module(_), do: Profile.error("skills.modules", "Expected a skill module")
  defp trust(value) when is_boolean(value), do: {:ok, value}
  defp trust({module, function}), do: trust({module, function, []})

  defp trust({module, function, args} = value)
       when is_atom(module) and is_atom(function) and is_list(args) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, 1 + length(args)),
      do: {:ok, value},
      else: Profile.error("skills.trust", "Expected an exported trust callback")
  end

  defp trust(_), do: Profile.error("skills.trust", "Use a boolean or a static MFA callback")

  @doc false
  def prepare_all(sources) do
    Profile.traverse(Map.to_list(sources), fn {id, source} ->
      with {:ok, source} <- new(source),
           {:ok, catalog} <- prepare(source),
           do: {:ok, {id, catalog}}
    end)
    |> case do
      {:ok, pairs} -> {:ok, Map.new(pairs)}
      error -> error
    end
  end

  defp prepare(source) do
    source =
      Map.update!(source, :trust, fn
        {module, function, args} -> fn path -> apply(module, function, [path | args]) end
        value -> value
      end)

    AgentIntegration.prepare(Map.to_list(source))
  end

  @doc false
  def profiles(profiles, catalogs, defaults \\ %{}) do
    Profile.traverse(Map.to_list(profiles), fn {id, profile} ->
      case {profile.skills, catalogs[id]} do
        {nil, _} ->
          {:ok, {id, profile}}

        {_, nil} ->
          Profile.error("skills", "Automatic skills require a live Agent Session")

        {_, catalog} ->
          names = MapSet.new(profile.tools, & &1.name)
          actions = Enum.uniq(catalog.tools ++ Enum.flat_map(catalog.specs, & &1.actions))

          with {:ok, tools} <-
                 ToolCatalog.from_input(actions, Map.put(defaults, :forward_context, :all)),
               tools = profile.tools ++ Enum.reject(tools, &MapSet.member?(names, &1.name)),
               prompt =
                 Enum.reject([profile.instructions, catalog.index], &(&1 in [nil, ""]))
                 |> Enum.join("\n\n"),
               {:ok, profile} <-
                 Profile.new(%{
                   profile
                   | tools: tools,
                     instructions: if(prompt == "", do: nil, else: prompt)
                 }),
               do: {:ok, {id, profile}}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Map.new(pairs)}
      error -> error
    end
  end

  @doc false
  def context(context, %{id: id}, catalogs) do
    case catalogs[id] do
      nil ->
        context

      catalog ->
        context
        |> Map.drop(
          Jido.AI.Skill.Runtime.reserved_keys() ++
            Enum.map(Jido.AI.Skill.Runtime.reserved_keys(), &Atom.to_string/1)
        )
        |> Map.merge(catalog.tool_context)
        |> Map.put_new(Jido.AI.Actions.Skill.LoadSkill.context_skills_key(), %{})
    end
  end

  def context(context, _, _), do: context
end
