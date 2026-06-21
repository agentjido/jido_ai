defmodule Jido.AI.Actions.Skill.LoadSkill do
  @moduledoc """
  A Jido.Action for lazily loading registered skill instructions.

  Pair this action with `Jido.AI.Skill.Prompt.render_registry_index/1` to expose
  a compact skill index in an agent prompt. The model can call `load_skill` only
  after selecting a relevant skill, keeping full skill bodies out of the prompt
  until they are needed.

  ## Parameters

  * `name` (required) - Registered skill name to load.
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
    Loads the full instructions for a registered skill by name. Call this after
    selecting a skill from a compact skill index.
    """,
    category: "ai",
    tags: ["skills", "lazy-loading"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        name: Zoi.string(description: "The registered skill name to load"),
        include_metadata:
          Zoi.boolean(description: "Include metadata such as tags and allowed tools")
          |> Zoi.default(true)
          |> Zoi.optional()
      })

  alias Jido.AI.Skill
  alias Jido.AI.Skill.{Registry, Spec}
  alias Jido.AI.Validation

  @doc """
  Loads the requested skill body from the registry.
  """
  @impl Jido.Action
  def run(params, _context) do
    with {:ok, name} <- validate_name(params[:name]) do
      case Skill.resolve(name) do
        {:ok, %Spec{} = spec} ->
          {:ok, payload(spec, params[:include_metadata] != false)}

        {:error, _reason} ->
          {:error,
           %{
             type: :skill_not_found,
             message: "Unknown skill '#{name}'",
             available_skills: Registry.list() |> Enum.sort()
           }}
      end
    end
  end

  defp validate_name(name) when is_binary(name) do
    name = String.trim(name)

    with false <- name == "",
         {:ok, _name} <- Validation.validate_string(name, max_length: 128, allow_empty: false) do
      {:ok, name}
    else
      true -> {:error, %{type: :invalid_skill_name, message: "Skill name is required"}}
      {:error, reason} -> {:error, %{type: :invalid_skill_name, message: "Invalid skill name", reason: reason}}
    end
  end

  defp validate_name(_), do: {:error, %{type: :invalid_skill_name, message: "Skill name is required"}}

  defp payload(%Spec{} = spec, true) do
    spec
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

  defp payload(%Spec{} = spec, false) do
    %{
      name: spec.name,
      description: spec.description,
      instructions: Skill.body(spec)
    }
  end
end
