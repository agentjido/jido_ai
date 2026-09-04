defmodule Jido.AI.Skill.AgentIntegration do
  @moduledoc """
  Builds the Agent Skills catalog, loading tool, and reserved tool context for a
  `Jido.AI.Agent` when the agent instance initializes.

  Discovery is explicit because scanning a project loads instructions from its
  filesystem. Passing `true` trusts the standard project and user skill roots;
  passing a list trusts only those roots. Keyword options expose the discovery
  bounds and a custom trust predicate. Keyword options do not trust any root
  unless `:trust` is explicitly set.

  Hosts may also pass runtime `%Jido.AI.Skill.Spec{}` values with `source: nil`
  and inline bodies:

      agent_skills: [
        specs: runtime_specs,
        resource_provider: &MyApp.SkillResources.handle/2,
        resource_policy: [max_text_bytes: 131_072]
      ]

  Runtime specs are validated, preserved without filesystem discovery or
  filesystem roots, and added to the same scoped catalog as discovered skills.
  Runtime specs take precedence over discovered skills with the same name;
  shadowed discovered entries are reported in diagnostics. Duplicate runtime
  names are rejected.

  The catalog contains metadata-only discovered specs. Full files are read and
  strictly validated only after the model selects a filesystem skill. Runtime
  specs keep their inline body and metadata exactly as supplied.

  Enabled agents receive both `load_skill` and `load_skill_resource`. The
  optional `:resource_policy` sets listing and text-loading limits for both
  actions.
  """

  alias Jido.AI.Actions.Skill.{LoadResource, LoadSkill}
  alias Jido.AI.Skill.{Diagnostics, Discovery, Prompt, ResourcePolicy, ResourceProvider, Resources, Spec}

  @type t :: %{
          specs: [Spec.t()],
          index: String.t(),
          tools: [module()],
          tool_context: map(),
          diagnostics: Diagnostics.t()
        }

  @doc """
  Prepares Agent Skills integration data.

  Accepted values:

  - `false` or `nil` - disable Agent Skills integration
  - `true` - trust and discover the standard project and user roots
  - a list of paths - trust and discover only those roots
  - keyword options - accepts `:specs`, `:resource_provider`, `:paths`,
    `:trust`, `:max_depth`, `:max_directories`, `:exclude_directories`, and
    `:resource_policy`
  """
  @spec prepare(false | nil | true | [String.t()] | keyword()) :: {:ok, t()} | {:error, term()}
  def prepare(value \\ false)

  def prepare(value) when value in [false, nil], do: {:ok, empty()}

  def prepare(true), do: prepare(paths: :default, trust: true)

  def prepare([]), do: {:ok, empty()}

  def prepare(paths) when is_list(paths) do
    cond do
      Keyword.keyword?(paths) ->
        prepare_options(paths)

      Enum.all?(paths, &is_binary/1) ->
        prepare_options(paths: paths, trust: true)

      true ->
        {:error, {:invalid_agent_skills_option, :paths}}
    end
  end

  def prepare(_value), do: {:error, {:invalid_agent_skills_option, :expected_boolean_paths_or_keyword}}

  @doc false
  @spec prepare!(false | nil | true | [String.t()] | keyword()) :: t()
  def prepare!(value \\ false) do
    case prepare(value) do
      {:ok, integration} -> integration
      {:error, reason} -> raise ArgumentError, "invalid agent_skills configuration: #{inspect(reason)}"
    end
  end

  defp prepare_options(opts) do
    runtime_specs_or_opts = Keyword.get(opts, :specs, [])
    paths = paths_option(opts, runtime_specs_or_opts)
    policy_or_opts = Keyword.get(opts, :resource_policy, ResourcePolicy.default())
    provider_or_nil = Keyword.get(opts, :resource_provider)

    discovery_opts =
      opts
      |> Keyword.take([:trust, :max_depth, :max_directories, :exclude_directories])
      |> Keyword.put_new(:trust, false)

    with {:ok, runtime_specs} <- runtime_specs(runtime_specs_or_opts),
         {:ok, provider} <- ResourceProvider.validate(provider_or_nil),
         {:ok, resource_policy} <- ResourcePolicy.new(policy_or_opts),
         {:ok, metadata, diagnostics} <- discover(paths, discovery_opts),
         {:ok, discovered_specs} <- catalog_specs(metadata),
         {specs, diagnostics} <- merge_specs(runtime_specs, discovered_specs, diagnostics) do
      specs = Enum.sort_by(specs, & &1.name)
      tool_context = tool_context(specs, provider, resource_policy)

      {:ok,
       %{
         specs: specs,
         index: Prompt.render_index(specs),
         tools: if(specs == [], do: [], else: [LoadSkill, LoadResource]),
         tool_context: tool_context,
         diagnostics: diagnostics
       }}
    end
  end

  defp paths_option(opts, runtime_specs) do
    cond do
      Keyword.has_key?(opts, :paths) -> Keyword.get(opts, :paths)
      runtime_specs != [] -> []
      true -> :default
    end
  end

  defp discover(:default, opts), do: Discovery.discover_with_diagnostics(opts)

  defp discover(paths, opts) when is_list(paths),
    do: Discovery.discover_from_with_diagnostics(paths, opts)

  defp discover(_paths, _opts), do: {:error, {:invalid_agent_skills_option, :paths}}

  defp catalog_specs(metadata) do
    Enum.reduce_while(metadata, {:ok, []}, fn item, {:ok, specs} ->
      case Discovery.to_catalog_spec(item) do
        {:ok, spec} -> {:cont, {:ok, [spec | specs]}}
        {:error, reason} -> {:halt, {:error, {:skill_load_failed, item.skill_md_path, reason}}}
      end
    end)
  end

  defp runtime_specs(specs) when is_list(specs) do
    specs
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], %{}}, fn {spec, index}, {:ok, acc, names} ->
      with {:ok, %Spec{name: name} = spec} <- Spec.validate_runtime(spec, index: index),
           :ok <- unique_runtime_name(name, index, names) do
        {:cont, {:ok, [spec | acc], Map.put(names, name, index)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, specs, _names} -> {:ok, Enum.reverse(specs)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp runtime_specs(_specs), do: {:error, {:invalid_agent_skills_option, :specs}}

  defp unique_runtime_name(name, index, names) do
    case Map.fetch(names, name) do
      :error -> :ok
      {:ok, first_index} -> {:error, {:duplicate_runtime_skill, name, first_index, index}}
    end
  end

  defp merge_specs(runtime_specs, discovered_specs, diagnostics) do
    Enum.reduce(
      discovered_specs,
      {Enum.reverse(runtime_specs), Map.new(runtime_specs, &{&1.name, &1}), diagnostics},
      fn spec, {selected, winners, diagnostics} ->
        case Map.fetch(winners, spec.name) do
          :error ->
            {[spec | selected], Map.put(winners, spec.name, spec), diagnostics}

          {:ok, winner} ->
            warning =
              Diagnostics.Warning.new(
                :shadowed_skill,
                "Skill '#{spec.name}' from #{source_label(spec)} is shadowed by #{source_label(winner)}",
                severity: :medium
              )

            {selected, winners, Diagnostics.add_warning(diagnostics, warning)}
        end
      end
    )
    |> then(fn {selected, _winners, diagnostics} -> {Enum.reverse(selected), diagnostics} end)
  end

  defp source_label(%Spec{source: {:file, path}}), do: "'#{path}'"
  defp source_label(%Spec{}), do: "a runtime spec"

  defp tool_context([], _provider, _resource_policy), do: %{}

  defp tool_context(specs, provider, resource_policy) do
    base = %{
      LoadSkill.context_skills_key() => Map.new(specs, &{&1.name, &1}),
      Resources.context_policy_key() => resource_policy
    }

    if provider do
      Map.put(base, ResourceProvider.context_provider_key(), provider)
    else
      base
    end
  end

  defp empty do
    %{specs: [], index: "", tools: [], tool_context: %{}, diagnostics: Diagnostics.new()}
  end
end
