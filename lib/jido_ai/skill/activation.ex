defmodule Jido.AI.Skill.Activation do
  @moduledoc """
  First-class activation API for skills.

  Manages skill activation lifecycle:
  - Prevents duplicate activation (idempotent within session)
  - Scopes activation by an explicit session ID or the caller process
  - Returns activation context for host/client injection
  - Tracks activated skills for session management

  ## Activation Context

  The context returned on activation includes:
  - `skill` - The full `Jido.AI.Skill.Spec`
  - `skill_body` - The rendered skill body text
  - `root_dir` - Skill root directory for resource resolution
  - `resources` - Listing of bundled resources
  - `resource_policy` - Policy captured at activation time
  - `resource_provider` - Optional provider binding for runtime resources

  Filesystem skills list bundled resources from their skill root. Runtime specs
  may pass a `:resource_provider` binding in options; that provider is used for
  listing during activation and stored for fresh `load_skill_resource` calls.

  ## Usage

      # Activate a registered skill by name
      {:ok, context} = Jido.AI.Skill.Activation.activate("code-review")

      # Search trusted paths only when you give both options
      {:ok, context} =
        Jido.AI.Skill.Activation.activate("code-review",
          paths: ["priv/skills"],
          trust: true
        )

      # Check if already activated
      Jido.AI.Skill.Activation.activated?("code-review")
  """

  alias Jido.AI.Skill.{Discovery, Loader, Registry, ResourcePolicy, ResourceProvider, Resources, Spec}

  @discovery_option_keys [:trust, :max_depth, :max_directories, :exclude_directories]

  @type activation_context :: %{
          skill: Spec.t(),
          skill_body: String.t(),
          root_dir: String.t() | nil,
          resources: Resources.resource_listing() | ResourceProvider.resource_listing(),
          resource_policy: ResourcePolicy.t(),
          resource_provider: ResourceProvider.binding() | nil,
          resource_backend: :filesystem | :provider | :none,
          provider_resource_ids: MapSet.t(String.t())
        }

  @doc """
  Activates a skill by name, spec, or module.

  Returns activation context for use in host/client injection.
  Prevents duplicate activation within the same session. Pass `:session_id`
  when the session spans processes; otherwise the caller process is used.

  Name activation first checks the registry. It does not scan the filesystem
  unless `:paths` and `:trust` are both present. A metadata-only catalog spec is
  loaded and strictly validated from its source file at activation time.

  ## Returns

  - `{:ok, context}` - Skill activated (or was already active)
  - `{:error, reason}` - Activation failed

  ## Examples

      {:ok, context} = Jido.AI.Skill.Activation.activate("code-review")
      IO.puts(context.skill_body)
  """
  @spec activate(String.t() | Spec.t() | module(), keyword()) ::
          {:ok, activation_context()} | {:error, term()}
  def activate(skill, opts \\ [])

  def activate(name, opts) when is_binary(name) do
    # First check if already activated
    if Registry.activated?(name, opts) do
      # Return existing activation context
      build_context_from_registry(name, opts)
    else
      # Try to resolve the skill
      with {:ok, spec} <- resolve_skill(name, opts),
           {:ok, resolved_spec} <- resolve_activation_spec(spec) do
        do_activate(resolved_spec, opts)
      end
    end
  end

  def activate(%Spec{} = spec, opts) do
    activate_spec(spec, opts)
  end

  def activate(mod, opts) when is_atom(mod) do
    # Module-based skills
    if function_exported?(mod, :manifest, 0) do
      case mod.manifest() do
        %Spec{} = spec -> activate_spec(spec, opts)
        _other -> {:error, :invalid_skill_module}
      end
    else
      {:error, :invalid_skill_module}
    end
  end

  @doc """
  Activates a skill, raising on error.
  """
  @spec activate!(String.t() | Spec.t() | module(), keyword()) :: activation_context()
  def activate!(skill, opts \\ []) do
    case activate(skill, opts) do
      {:ok, context} -> context
      {:error, reason} -> raise "Skill activation failed: #{inspect(reason)}"
    end
  end

  @doc """
  Activates multiple skills in a batch.

  Returns results for each activation, with `:ok` or `:error` tuples.

  ## Examples

      results = Jido.AI.Skill.Activation.activate_batch(["code-review", "testing"])
      # Returns: [{:ok, context1}, {:ok, context2}] or with errors
  """
  @spec activate_batch([String.t() | Spec.t() | module()], keyword()) ::
          [{:ok, activation_context()} | {:error, term()}]
  def activate_batch(skills, opts \\ []) do
    Enum.map(skills, fn skill ->
      case activate(skill, opts) do
        {:ok, context} -> {:ok, context}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @doc """
  Lists all activated skills in the selected session.

  ## Examples

      ["code-review", "testing"] = Jido.AI.Skill.Activation.list_activated()
  """
  @spec list_activated(keyword()) :: [String.t()]
  def list_activated(opts \\ []) do
    Registry.list_activated(opts)
  end

  @doc """
  Returns true if the named skill is activated in the selected session.

  ## Examples

      Jido.AI.Skill.Activation.activated?("code-review")
  """
  @spec activated?(String.t(), keyword()) :: boolean()
  def activated?(name, opts \\ []) when is_binary(name) do
    Registry.activated?(name, opts)
  end

  @doc """
  Returns the activation context for a skill without activating it.

  ## Returns

  - `{:ok, context}` - Skill is activated, context returned
  - `{:error, :not_activated}` - Skill not activated

  ## Examples

      {:ok, context} = Jido.AI.Skill.Activation.get_context("code-review")
  """
  @spec get_context(String.t(), keyword()) :: {:ok, activation_context()} | {:error, :not_activated}
  def get_context(name, opts \\ []) when is_binary(name) do
    if Registry.activated?(name, opts) do
      build_context_from_registry(name, opts)
    else
      {:error, :not_activated}
    end
  end

  @doc """
  Clears all activations for the selected session.

  Pass the same `:session_id` used for activation. Without one, the caller
  process is used.
  """
  @spec clear(keyword()) :: :ok | {:error, term()}
  def clear(opts \\ []), do: Registry.clear_activations(opts)

  # Private functions

  defp activate_spec(%Spec{name: name} = spec, opts) when is_binary(name) do
    if Registry.activated?(name, opts) do
      build_context_from_registry(spec.name, opts)
    else
      with {:ok, resolved_spec} <- resolve_activation_spec(spec) do
        do_activate(resolved_spec, opts)
      end
    end
  end

  defp activate_spec(%Spec{}, _opts), do: {:error, :invalid_skill_spec}

  defp resolve_skill(name, opts) when is_binary(name) do
    case Registry.lookup(name) do
      {:ok, spec} ->
        {:ok, spec}

      {:error, _} ->
        resolve_discovered_skill(name, opts)
    end
  end

  defp resolve_discovered_skill(name, opts) do
    case {Keyword.fetch(opts, :paths), Keyword.fetch(opts, :trust)} do
      {{:ok, paths}, {:ok, _trust}} ->
        discovery_opts = Keyword.take(opts, @discovery_option_keys)

        result =
          case paths do
            :default -> Discovery.find(name, nil, discovery_opts)
            paths when is_list(paths) -> Discovery.find(name, paths, discovery_opts)
            _invalid -> {:error, {:invalid_discovery_option, :paths}}
          end

        case result do
          {:ok, metadata} -> Discovery.to_spec(metadata, lenient: false)
          {:error, :not_found} -> {:error, :skill_not_found}
          {:error, reason} -> {:error, reason}
        end

      {{:ok, _paths}, :error} ->
        {:error, :filesystem_discovery_requires_explicit_trust}

      _ ->
        {:error, :skill_not_found}
    end
  end

  defp resolve_activation_spec(%Spec{
         source: {:file, path},
         body_ref: {:file, path},
         metadata: %{"jido_ai.discovery_scope" => _scope} = catalog_metadata
       }) do
    case Loader.load(path, lenient: false) do
      {:ok, spec} -> {:ok, %{spec | metadata: Map.merge(spec.metadata, catalog_metadata)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_activation_spec(%Spec{} = spec), do: {:ok, spec}

  defp do_activate(%Spec{} = spec, opts) do
    with {:ok, skill_body} <- load_skill_body(spec),
         {:ok, context} <- activation_context(spec, skill_body, opts),
         :ok <- Registry.mark_activated(spec.name, context, opts) do
      # Return the registry's canonical context so the first activation and any
      # subsequent (idempotent) activations yield an identical result.
      build_context_from_registry(spec.name, opts)
    end
  end

  defp build_context_from_registry(name, opts) do
    Registry.get_activation_context(name, opts)
  end

  defp activation_context(%Spec{} = spec, skill_body, opts) do
    root_dir = root_dir(spec)
    policy_or_opts = Keyword.get(opts, :resource_policy, ResourcePolicy.default())
    provider_binding = Keyword.get(opts, :resource_provider)

    with {:ok, policy} <- ResourcePolicy.new(policy_or_opts),
         {:ok, resources, resource_backend, provider_resource_ids} <-
           list_resources(spec, root_dir, policy, provider_binding) do
      {:ok,
       %{
         skill: spec,
         skill_body: skill_body,
         root_dir: root_dir,
         resources: resources,
         resource_policy: policy,
         resource_provider: provider_binding,
         resource_backend: resource_backend,
         provider_resource_ids: provider_resource_ids
       }}
    end
  end

  defp load_skill_body(%Spec{body_ref: {:file, path}}) do
    case File.read(path) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, {:body_load_failed, reason}}
    end
  end

  defp load_skill_body(%Spec{} = spec), do: {:ok, Jido.AI.Skill.body(spec)}

  defp root_dir(%Spec{source: {:file, path}}), do: Path.dirname(path)
  defp root_dir(%Spec{}), do: nil

  defp list_resources(%Spec{} = spec, _root_dir, policy, %{provider: provider, context: context}) do
    with {:ok, resources} <- ResourceProvider.list(provider, spec, policy, context) do
      {:ok, resources, :provider, MapSet.new(resources.resources, & &1.id)}
    end
  end

  defp list_resources(_spec, nil, policy, _provider_binding) do
    with {:ok, resources} <- Resources.empty_listing(policy) do
      {:ok, resources, :none, MapSet.new()}
    end
  end

  defp list_resources(_spec, root_dir, policy, _provider_binding) do
    with {:ok, resources} <- Resources.list_all(root_dir, policy) do
      {:ok, resources, :filesystem, MapSet.new()}
    end
  end
end
