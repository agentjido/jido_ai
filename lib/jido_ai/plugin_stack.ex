defmodule Jido.AI.PluginStack do
  @moduledoc """
  Centralized default plugin composition for Jido.AI agent macros.

  ## Opting out of / reconfiguring default plugins

  Every agent built with `use Jido.AI.Agent` gets
  `TaskSupervisor`, `Policy`, and `ModelRouting` by default. Two
  options let callers customise that stack:

    * `:skip_default_plugins` — list of default-plugin modules to
      drop from the stack. Typical when a default plugin's
      defaults conflict with a specialised agent (e.g. the
      100 KB / injection-pattern gate in `Policy` is wrong for an
      agent that receives server-generated audit prompts rather
      than user input).
    * `:default_plugin_config` — keyword list keyed by default
      plugin module; each value is a map (or keyword list) merged
      into the plugin's `mount/2` config. Used to tune a default
      plugin without replacing it wholesale.

  `:default_plugin_config` takes precedence over
  `:skip_default_plugins` — if a module appears in both, it is
  kept (reconfigured, not removed).

  ## Examples

      # Reconfigure Policy to run in :monitor mode
      use Jido.AI.Agent,
        name: "audit_agent",
        default_plugin_config: [
          {Jido.AI.Plugins.Policy, %{mode: :monitor, block_on_validation_error: false}}
        ]

      # Drop Policy entirely (Agent still composes with ToolGuard
      # and other callers' guardrails)
      use Jido.AI.Agent,
        name: "trusted_internal_agent",
        skip_default_plugins: [Jido.AI.Plugins.Policy]
  """

  @default_plugins [
    Jido.AI.Plugins.TaskSupervisor,
    Jido.AI.Plugins.Policy,
    Jido.AI.Plugins.ModelRouting
  ]

  @doc """
  Returns the default runtime plugin list for AI agent macros.

  Always includes `TaskSupervisor`, `Policy`, and `ModelRouting`
  unless overridden via `:skip_default_plugins` /
  `:default_plugin_config`. Optional plugins are enabled via
  `:retrieval` and `:quota` options.
  """
  @spec default_plugins(keyword()) :: [module() | {module(), map()}]
  def default_plugins(opts \\ []) when is_list(opts) do
    skip = Keyword.get(opts, :skip_default_plugins, []) |> List.wrap()
    overrides = Keyword.get(opts, :default_plugin_config, []) |> normalise_overrides()

    @default_plugins
    |> Enum.flat_map(fn plugin_module ->
      cond do
        Map.has_key?(overrides, plugin_module) ->
          [{plugin_module, Map.fetch!(overrides, plugin_module)}]

        plugin_module in skip ->
          []

        true ->
          [plugin_module]
      end
    end)
    |> maybe_add_optional(Jido.AI.Plugins.Retrieval, Keyword.get(opts, :retrieval, false))
    |> maybe_add_optional(Jido.AI.Plugins.Quota, Keyword.get(opts, :quota, false))
  end

  defp normalise_overrides(list) when is_list(list) do
    Enum.reduce(list, %{}, fn
      {module, config}, acc when is_atom(module) and is_map(config) ->
        Map.put(acc, module, config)

      {module, config}, acc when is_atom(module) and is_list(config) ->
        Map.put(acc, module, Map.new(config))

      _other, acc ->
        acc
    end)
  end

  defp normalise_overrides(_), do: %{}

  defp maybe_add_optional(plugins, _module, false), do: plugins
  defp maybe_add_optional(plugins, module, true), do: plugins ++ [module]

  defp maybe_add_optional(plugins, module, config) when is_map(config),
    do: plugins ++ [{module, config}]

  defp maybe_add_optional(plugins, module, config) when is_list(config),
    do: plugins ++ [{module, Map.new(config)}]

  defp maybe_add_optional(plugins, _module, _), do: plugins
end
