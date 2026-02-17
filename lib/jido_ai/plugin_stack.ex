defmodule Jido.AI.PluginStack do
  @moduledoc false

  @task_supervisor_plugin Jido.AI.Plugins.TaskSupervisor
  @policy_plugin Jido.AI.Plugins.Policy

  @type plugin_decl :: module() | {module(), map() | keyword()}
  @type plugin_decl_ast ::
          {:__aliases__, list(), [atom()]}
          | {{:__aliases__, list(), [atom()]} | module(), map() | keyword()}
          | plugin_decl()

  @spec normalize_user_plugins([plugin_decl_ast()], Macro.Env.t()) :: [plugin_decl()]
  def normalize_user_plugins(plugins, caller_env) when is_list(plugins) do
    Enum.map(plugins, &normalize_plugin_decl(&1, caller_env))
  end

  @spec build([plugin_decl()], term()) :: [plugin_decl()]
  def build(plugins, policy_opt \\ true)

  def build(plugins, policy_opt) when is_list(plugins) do
    defaults =
      [@task_supervisor_plugin]
      |> maybe_add_default_policy(policy_opt, plugins)

    merge_defaults(defaults, plugins)
  end

  def build(_plugins, _policy_opt) do
    raise ArgumentError, "plugins must be a list"
  end

  defp maybe_add_default_policy(defaults, false, _plugins), do: defaults
  defp maybe_add_default_policy(defaults, nil, plugins), do: maybe_add_default_policy(defaults, true, plugins)

  defp maybe_add_default_policy(defaults, true, plugins) do
    if plugin_present?(plugins, @policy_plugin) do
      defaults
    else
      defaults ++ [@policy_plugin]
    end
  end

  defp maybe_add_default_policy(defaults, policy_opts, plugins) when is_list(policy_opts) do
    if plugin_present?(plugins, @policy_plugin) do
      defaults
    else
      defaults ++ [{@policy_plugin, Map.new(policy_opts)}]
    end
  end

  defp maybe_add_default_policy(defaults, policy_opts, plugins) when is_map(policy_opts) do
    if plugin_present?(plugins, @policy_plugin) do
      defaults
    else
      defaults ++ [{@policy_plugin, policy_opts}]
    end
  end

  defp maybe_add_default_policy(_defaults, policy_opt, _plugins) do
    raise ArgumentError,
          ":policy must be false, true, a keyword list, or a map; got: #{inspect(policy_opt)}"
  end

  defp merge_defaults(defaults, user_plugins) do
    user_modules = user_plugins |> Enum.map(&plugin_module/1) |> MapSet.new()

    defaults_to_keep =
      defaults
      |> Enum.reduce({MapSet.new(), []}, fn plugin, {seen, acc} ->
        mod = plugin_module(plugin)

        cond do
          MapSet.member?(user_modules, mod) ->
            {seen, acc}

          MapSet.member?(seen, mod) ->
            {seen, acc}

          true ->
            {MapSet.put(seen, mod), [plugin | acc]}
        end
      end)
      |> elem(1)
      |> Enum.reverse()

    defaults_to_keep ++ user_plugins
  end

  defp plugin_present?(plugins, module) do
    Enum.any?(plugins, fn plugin -> plugin_module(plugin) == module end)
  end

  defp plugin_module({{:__aliases__, _, parts}, _opts}) when is_list(parts) do
    Module.concat(parts)
  end

  defp plugin_module({module, _opts}) when is_atom(module), do: module

  defp plugin_module({:__aliases__, _, parts}) when is_list(parts) do
    Module.concat(parts)
  end

  defp plugin_module(module) when is_atom(module), do: module

  defp normalize_plugin_decl({module_ast, opts_ast}, caller_env) do
    module = normalize_plugin_module(module_ast, caller_env)
    opts = normalize_plugin_opts(opts_ast, caller_env)
    {module, opts}
  end

  defp normalize_plugin_decl(module_ast, caller_env) do
    normalize_plugin_module(module_ast, caller_env)
  end

  defp normalize_plugin_module({:__aliases__, _, _} = alias_ast, caller_env) do
    Macro.expand(alias_ast, caller_env)
  end

  defp normalize_plugin_module(module, _caller_env) when is_atom(module), do: module

  defp normalize_plugin_opts({:%{}, _, _} = map_ast, caller_env) do
    expanded_ast = expand_aliases(map_ast, caller_env)
    {evaluated, _binding} = Code.eval_quoted(expanded_ast, [], caller_env)
    evaluated
  end

  defp normalize_plugin_opts(opts, caller_env) when is_list(opts) do
    if contains_alias_ast?(opts) do
      expanded_ast = expand_aliases(opts, caller_env)
      {evaluated, _binding} = Code.eval_quoted(expanded_ast, [], caller_env)
      evaluated
    else
      opts
    end
  end

  defp normalize_plugin_opts(opts, _caller_env) when is_map(opts), do: opts
  defp normalize_plugin_opts(opts, _caller_env), do: opts

  defp expand_aliases(ast, caller_env) do
    Macro.prewalk(ast, fn
      {:__aliases__, _, _} = alias_ast -> Macro.expand(alias_ast, caller_env)
      other -> other
    end)
  end

  defp contains_alias_ast?(term) do
    Macro.prewalk(term, false, fn
      {:__aliases__, _, _} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)
    |> elem(1)
  end
end
