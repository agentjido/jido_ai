defmodule Jido.AI.Skill.AgentIntegration do
  @moduledoc """
  Builds the Agent Skills catalog, loading tool, and reserved tool context for a
  `Jido.AI.Agent` at agent module compilation time.

  Discovery is explicit because scanning a project loads instructions from its
  filesystem. Passing `true` trusts the standard project and user skill roots;
  passing a list trusts only those roots. Keyword options expose the discovery
  bounds and a custom trust predicate. Keyword options do not trust any root
  unless `:trust` is explicitly set.
  """

  alias Jido.AI.Actions.Skill.LoadSkill
  alias Jido.AI.Skill.{Discovery, Prompt, Spec}

  @type t :: %{
          specs: [Spec.t()],
          index: String.t(),
          tools: [module()],
          tool_context: map()
        }

  @doc """
  Prepares Agent Skills integration data.

  Accepted values:

  - `false` or `nil` - disable Agent Skills integration
  - `true` - trust and discover the standard project and user roots
  - a list of paths - trust and discover only those roots
  - keyword options - accepts `:paths`, `:trust`, `:max_depth`,
    `:max_directories`, and `:exclude_directories`
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
    paths = Keyword.get(opts, :paths, :default)

    discovery_opts =
      opts
      |> Keyword.take([:trust, :max_depth, :max_directories, :exclude_directories])
      |> Keyword.put_new(:trust, false)

    with {:ok, metadata} <- discover(paths, discovery_opts),
         {:ok, specs} <- load_specs(metadata) do
      specs = Enum.sort_by(specs, & &1.name)

      {:ok,
       %{
         specs: specs,
         index: Prompt.render_index(specs),
         tools: if(specs == [], do: [], else: [LoadSkill]),
         tool_context: %{LoadSkill.context_skills_key() => Map.new(specs, &{&1.name, &1})}
       }}
    end
  end

  defp discover(:default, opts), do: Discovery.discover(opts)
  defp discover(paths, opts) when is_list(paths), do: Discovery.discover_from(paths, opts)
  defp discover(_paths, _opts), do: {:error, {:invalid_agent_skills_option, :paths}}

  defp load_specs(metadata) do
    Enum.reduce_while(metadata, {:ok, []}, fn item, {:ok, specs} ->
      case Discovery.to_spec(item) do
        {:ok, spec} -> {:cont, {:ok, [spec | specs]}}
        {:error, reason} -> {:halt, {:error, {:skill_load_failed, item.skill_md_path, reason}}}
      end
    end)
  end

  defp empty do
    %{specs: [], index: "", tools: [], tool_context: %{}}
  end
end
