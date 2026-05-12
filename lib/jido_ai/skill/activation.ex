defmodule Jido.AI.Skill.Activation do
  @moduledoc """
  First-class activation API for skills.

  Manages skill activation lifecycle:
  - Prevents duplicate activation (idempotent within session)
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
  Prevents duplicate activation within the same session.

  ## Returns

  - `{:ok, context}` - Skill activated (or was already active)
  - `{:error, reason}` - Activation failed

  ## Examples

      {:ok, context} = Jido.AI.Skill.Activation.activate("code-review")
      IO.puts(context.skill_body)
  """
  @spec activate(String.t() | Spec.t() | module()) :: {:ok, activation_context()} | {:error, term()}
  def activate(name) when is_binary(name) do
    # First check if already activated
    if Registry.activated?(name) do
      # Return existing activation context
      {:ok, build_context_from_registry(name)}
    else
      # Try to resolve the skill
      with {:ok, spec} <- resolve_skill(name),
           {:ok, context} <- do_activate(spec) do
        {:ok, context}
      end
    end
  end

  def activate(%Spec{} = spec) do
    if Registry.activated?(spec.name) do
      {:ok, build_context_from_registry(spec.name)}
    else
      do_activate(spec)
    end
  end

  def activate(mod) when is_atom(mod) do
    # Module-based skills
    if function_exported?(mod, :manifest, 0) do
      spec = mod.manifest()

      if Registry.activated?(spec.name) do
        {:ok, build_context_from_registry(spec.name)}
      else
        do_activate(spec)
      end
    else
      {:error, :invalid_skill_module}
    end
  end

  @doc """
  Activates a skill, raising on error.
  """
  @spec activate!(String.t() | Spec.t() | module()) :: activation_context()
  def activate!(skill) do
    case activate(skill) do
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
  @spec activate_batch([String.t() | Spec.t() | module()]) ::
          [{:ok, activation_context()} | {:error, term()}]
  def activate_batch(skills) do
    Enum.map(skills, fn skill ->
      case activate(skill) do
        {:ok, context} -> {:ok, context}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @doc """
  Lists all currently activated skills.

  ## Examples

      ["code-review", "testing"] = Jido.AI.Skill.Activation.list_activated()
  """
  @spec list_activated() :: [String.t()]
  def list_activated do
    Registry.list_activated()
  end

  @doc """
  Returns the activation context for a skill without activating it.

  ## Returns

  - `{:ok, context}` - Skill is activated, context returned
  - `{:error, :not_activated}` - Skill not activated

  ## Examples

      {:ok, context} = Jido.AI.Skill.Activation.get_context("code-review")
  """
  @spec get_context(String.t()) :: {:ok, activation_context()} | {:error, :not_activated}
  def get_context(name) when is_binary(name) do
    if Registry.activated?(name) do
      {:ok, build_context_from_registry(name)}
    else
      {:error, :not_activated}
    end
  end

  # Private functions

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

  defp do_activate(%Spec{} = spec) do
    # Extract root directory from source
    root_dir =
      case spec.source do
        {:file, path} -> Path.dirname(path)
        _ -> nil
      end

    # Get skill body
    skill_body = Jido.AI.Skill.body(spec)

    # List resources
    resources =
      if root_dir do
        Resources.list_resources(root_dir)
      else
        %{scripts: [], references: [], assets: []}
      end

    # Build context
    context = %{
      skill: spec,
      skill_body: skill_body,
      root_dir: root_dir,
      resources: resources
    }

    # Mark as activated in registry
    :ok = Registry.mark_activated(spec.name, context)

    {:ok, context}
  end

  defp build_context_from_registry(name) do
    Registry.get_activation_context(name)
  end
end
