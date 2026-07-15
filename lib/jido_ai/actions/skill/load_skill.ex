defmodule Jido.AI.Actions.Skill.LoadSkill do
  @moduledoc """
  A Jido.Action for lazily loading available skill instructions.

  Pair this action with `Jido.AI.Skill.Prompt.render_registry_index/1` to expose
  a compact skill index in an agent prompt. The model can call `load_skill` only
  after selecting a relevant skill, keeping full skill bodies out of the prompt
  until they are needed.

  The action routes through `Jido.AI.Skill.Activation`, returning the skill root
  and a bounded resource listing with the instructions. It scopes activation
  from `session_id`, `agent_id`, or `request_id` in the runtime context and tags
  the resulting tool message as durable for ReAct compaction.

  ## Parameters

  * `name` (required) - Available skill name to load.
  * `include_metadata` (optional) - Include skill metadata in the response
    (default: `true`).

  ## Examples

      {:ok, result} =
        Jido.Exec.run(Jido.AI.Actions.Skill.LoadSkill, %{name: "code-review"})

      result.instructions
      #=> "# Code Review..."
  """

  use Jido.Action,
    name: "load_skill",
    description: """
    Loads the full instructions for an available skill by name. Call this after
    selecting a skill from a compact skill index.
    """,
    category: "ai",
    tags: ["skills", "lazy-loading"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        name: Zoi.string(description: "The available skill name to load"),
        include_metadata:
          Zoi.boolean(description: "Include metadata such as tags and allowed tools")
          |> Zoi.default(true)
          |> Zoi.optional()
      })

  alias Jido.AI.Skill.{Activation, Registry, Spec}
  alias Jido.AI.Validation

  @name_regex ~r/^[a-z0-9]+(-[a-z0-9]+)*$/
  @max_name_length 64
  @context_skills_key :__jido_ai_agent_skills__

  @doc false
  def context_skills_key, do: @context_skills_key

  @doc """
  Loads and activates the requested skill from the agent catalog or registry.
  """
  @impl Jido.Action
  def run(params, context) when is_map(params) do
    context = if is_map(context), do: context, else: %{}

    with {:ok, name} <- validate_name(param(params, :name)),
         {:ok, include_metadata?} <- validate_include_metadata(param(params, :include_metadata, true)),
         {:ok, activation} <- activate_skill(name, context) do
      {:ok, payload(activation, include_metadata?)}
    end
  end

  def run(_params, _context), do: {:error, %{type: :invalid_params, message: "Parameters must be a map"}}

  defp param(params, key, default \\ nil) do
    Map.get(params, key, Map.get(params, Atom.to_string(key), default))
  end

  defp validate_name(nil), do: {:error, %{type: :invalid_skill_name, message: "Skill name is required"}}

  defp validate_name(name) do
    case Validation.validate_string(name, max_length: @max_name_length, allow_empty: false) do
      {:ok, name} -> validate_name_format(name)
      {:error, :empty_string} -> {:error, %{type: :invalid_skill_name, message: "Skill name is required"}}
      {:error, reason} -> {:error, %{type: :invalid_skill_name, message: "Invalid skill name", reason: reason}}
    end
  end

  defp validate_name_format(name) do
    if Regex.match?(@name_regex, name) do
      {:ok, name}
    else
      {:error, %{type: :invalid_skill_name, message: "Invalid skill name", reason: :invalid_format}}
    end
  end

  defp validate_include_metadata(nil), do: {:ok, true}
  defp validate_include_metadata(include_metadata?) when is_boolean(include_metadata?), do: {:ok, include_metadata?}

  defp validate_include_metadata(_include_metadata?) do
    {:error,
     %{
       type: :invalid_include_metadata,
       message: "include_metadata must be a boolean"
     }}
  end

  defp activate_skill(name, context) do
    skill = Map.get(agent_skill_specs(context), name, name)
    opts = [session_id: activation_session_id(context)]

    case Activation.activate(skill, opts) do
      {:ok, activation} ->
        with :ok <- Registry.mark_durable(name, opts) do
          {:ok, activation}
        end

      {:error, :skill_not_found} ->
        skill_not_found(name, context)

      {:error, {:body_load_failed, reason}} ->
        skill_body_unavailable(name, reason)

      {:error, reason} ->
        {:error, %{type: :skill_activation_failed, message: "Could not activate '#{name}'", reason: reason}}
    end
  end

  defp agent_skill_specs(context) do
    case Map.get(context, @context_skills_key, Map.get(context, Atom.to_string(@context_skills_key), %{})) do
      %{} = specs -> specs
      _ -> %{}
    end
  end

  defp activation_session_id(context) do
    context[:session_id] || context["session_id"] ||
      context[:agent_id] || context["agent_id"] ||
      context[:request_id] || context["request_id"] || self()
  end

  defp skill_not_found(name, context) do
    available_skills =
      context
      |> agent_skill_specs()
      |> Map.keys()
      |> Kernel.++(Registry.list())
      |> Enum.uniq()
      |> Enum.sort()

    {:error,
     %{
       type: :skill_not_found,
       message: "Unknown skill '#{name}'",
       available_skills: available_skills
     }}
  end

  defp skill_body_unavailable(name, reason) do
    {:error,
     %{
       type: :skill_body_unavailable,
       message: "Could not load skill body for '#{name}'",
       reason: reason
     }}
  end

  defp payload(%{skill: %Spec{} = spec} = activation, true) do
    activation
    |> payload(false)
    |> Map.merge(%{
      allowed_tools: spec.allowed_tools,
      tags: spec.tags,
      metadata: spec.metadata || %{},
      license: spec.license,
      compatibility: spec.compatibility,
      vsn: spec.vsn
    })
  end

  defp payload(%{skill: %Spec{} = spec} = activation, false) do
    %{
      name: spec.name,
      description: spec.description,
      instructions: activation.skill_body,
      root_dir: activation.root_dir,
      resources: activation.resources
    }
  end
end
