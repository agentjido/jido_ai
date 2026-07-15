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
  - `resources` - Bounded listing of bundled resources

  ## Usage

      # Activate by name (looks up in discovery and registry)
      {:ok, context} = Jido.AI.Skill.Activation.activate("code-review")

      # Activate a spec directly
      {:ok, spec} = Jido.AI.Skill.Discovery.find("code-review") |> Jido.AI.Skill.Discovery.to_spec()
      {:ok, context} = Jido.AI.Skill.Activation.activate(spec)

      # Check if already activated
      Jido.AI.Skill.Activation.activated?("code-review")
  """

  alias Jido.AI.Skill.{Spec, Registry, Discovery, Resources}

  @type activation_context :: %{
          skill: Spec.t(),
          skill_body: String.t(),
          root_dir: String.t() | nil,
          resources: Resources.resource_listing()
        }

  @doc """
  Activates a skill by name, spec, or module.

  Returns activation context for use in host/client injection.
  Prevents duplicate activation within the same session. Pass `:session_id`
  when the session spans processes; otherwise the caller process is used.

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
      with {:ok, spec} <- resolve_skill(name) do
        do_activate(spec, opts)
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

  # Private functions

  defp activate_spec(%Spec{name: name} = spec, opts) when is_binary(name) do
    if Registry.activated?(name, opts) do
      build_context_from_registry(spec.name, opts)
    else
      do_activate(spec, opts)
    end
  end

  defp activate_spec(%Spec{}, _opts), do: {:error, :invalid_skill_spec}

  defp resolve_skill(name) when is_binary(name) do
    # Try registry first
    case Registry.lookup(name) do
      {:ok, spec} ->
        {:ok, spec}

      {:error, _} ->
        # Try discovery
        case Discovery.find(name) do
          {:ok, metadata} -> Discovery.to_spec(metadata)
          {:error, _} -> {:error, :skill_not_found}
        end
    end
  end

  defp do_activate(%Spec{} = spec, opts) do
    with {:ok, skill_body} <- load_skill_body(spec),
         :ok <- Registry.mark_activated(spec.name, activation_context(spec, skill_body), opts) do
      # Return the registry's canonical context so the first activation and any
      # subsequent (idempotent) activations yield an identical result.
      build_context_from_registry(spec.name, opts)
    end
  end

  defp build_context_from_registry(name, opts) do
    Registry.get_activation_context(name, opts)
  end

  defp activation_context(%Spec{} = spec, skill_body) do
    root_dir = root_dir(spec)

    %{
      skill: spec,
      skill_body: skill_body,
      root_dir: root_dir,
      resources: list_resources(root_dir)
    }
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

  defp list_resources(nil), do: %{scripts: [], references: [], assets: []}
  defp list_resources(root_dir), do: Resources.list_resources(root_dir)
end
