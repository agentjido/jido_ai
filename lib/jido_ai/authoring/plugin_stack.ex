defmodule Jido.AI.PluginStack do
  @moduledoc """
  Default AI Plugin composition for public Agent macros.

  Policy and ModelRouting are enabled by default. Retrieval and Quota are
  optional. Core Session owns request work; the old TaskSupervisor Plugin is
  no longer inserted. Applications supervise optional stores before use.

  Map configuration is converted to the core keyword declaration. An explicit
  Plugin entry overrides the same default once, at its existing position.
  Repeated explicit modules are rejected. Public macros bind AI capability
  results to `:capability_result`, independently of the model answer.
  """
  alias Jido.AI.Plugins

  @defaults [Plugins.Policy, Plugins.ModelRouting]
  @capabilities [
    Plugins.Chat,
    Plugins.Planning,
    Plugins.Retrieval,
    Plugins.Quota,
    Plugins.Reasoning.ChainOfThought,
    Plugins.Reasoning.ChainOfDraft,
    Plugins.Reasoning.AlgorithmOfThoughts,
    Plugins.Reasoning.TreeOfThoughts,
    Plugins.Reasoning.GraphOfThoughts,
    Plugins.Reasoning.TRM,
    Plugins.Reasoning.Adaptive
  ]

  @doc "Returns Policy, ModelRouting and optional Retrieval/Quota declarations."
  @spec default_plugins(keyword()) :: [module() | {module(), keyword()}]
  def default_plugins(opts \\ []) when is_list(opts) do
    options!(opts)

    @defaults ++
      optional(Plugins.Retrieval, opts[:retrieval]) ++ optional(Plugins.Quota, opts[:quota])
  end

  @doc false
  def for_agent(opts) do
    defaults = Enum.map(default_plugins(opts), &declaration!/1)
    explicit = Keyword.get(opts, :plugins, [])
    unless is_list(explicit), do: raise(ArgumentError, "plugins must be a list")
    explicit = Enum.map(explicit, &declaration!/1)
    modules = Enum.map(explicit, &elem(&1, 0))

    if modules != Enum.uniq(modules),
      do: raise(ArgumentError, "Duplicate explicit AI Plugin modules")

    replacements = Map.new(explicit)
    default_modules = Enum.map(defaults, &elem(&1, 0))

    (Enum.map(defaults, fn {module, config} ->
       {module, Keyword.merge(config, Map.get(replacements, module, []))}
     end) ++ Enum.reject(explicit, &(elem(&1, 0) in default_modules)))
    |> Enum.map(fn {module, config} ->
      if module in @capabilities,
        do: {module, Keyword.put_new(config, :into, :capability_result)},
        else: {module, config}
    end)
  end

  @doc false
  def capability?(module), do: module in @capabilities

  @doc false
  def routes(plugins, explicit) do
    generated =
      Enum.flat_map(plugins, fn {module, config} ->
        if capability?(module), do: module.signal_routes(config), else: []
      end)

    with {:ok, explicit} <- Jido.Agent.Authoring.routes(explicit),
         {:ok, generated} <- Jido.Agent.Authoring.routes(generated) do
      keys = MapSet.new(explicit, &route_key/1)
      {:ok, explicit ++ Enum.reject(generated, &MapSet.member?(keys, route_key(&1)))}
    end
  end

  defp route_key(route), do: {route.path, route.match, route.priority}
  defp optional(_, value) when value in [nil, false], do: []
  defp optional(module, true), do: [module]

  defp optional(module, config) when is_map(config) or is_list(config),
    do: [{module, options!(config)}]

  defp optional(module, _),
    do:
      raise(
        ArgumentError,
        "#{inspect(module)} requires true, false, a map or keyword configuration"
      )

  defp declaration!(Plugins.TaskSupervisor),
    do:
      raise(
        ArgumentError,
        "TaskSupervisor is replaced by core Session work ownership; remove this Plugin"
      )

  defp declaration!({Plugins.TaskSupervisor, _}), do: declaration!(Plugins.TaskSupervisor)

  defp declaration!(module) when is_atom(module) and module not in [nil, true, false],
    do: {module, []}

  defp declaration!({module, config}) when is_atom(module) and module not in [nil, true, false],
    do: {module, options!(config)}

  defp declaration!(_), do: raise(ArgumentError, "Invalid AI Plugin declaration")

  defp options!(value) when is_map(value) and not is_struct(value),
    do: value |> Enum.sort() |> options!()

  defp options!(value) when is_list(value) do
    if Keyword.keyword?(value) and
         length(Keyword.keys(value)) == length(Enum.uniq(Keyword.keys(value))),
       do: value,
       else: raise(ArgumentError, "Plugin configuration requires unique atom keys")
  end

  defp options!(_), do: raise(ArgumentError, "Plugin configuration must be a map or keyword list")
end
