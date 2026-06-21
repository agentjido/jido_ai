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

  @name_regex ~r/^[a-z0-9]+(-[a-z0-9]+)*$/
  @max_name_length 64

  @doc """
  Loads the requested skill body from the registry.
  """
  @impl Jido.Action
  def run(params, _context) when is_map(params) do
    with {:ok, name} <- validate_name(param(params, :name)),
         {:ok, include_metadata?} <- validate_include_metadata(param(params, :include_metadata, true)),
         {:ok, %Spec{} = spec} <- resolve_skill(name),
         {:ok, instructions} <- load_instructions(spec) do
      {:ok, payload(spec, instructions, include_metadata?)}
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

  defp resolve_skill(name) do
    case Skill.resolve(name) do
      {:ok, %Spec{} = spec} ->
        {:ok, spec}

      {:error, _reason} ->
        {:error,
         %{
           type: :skill_not_found,
           message: "Unknown skill '#{name}'",
           available_skills: Registry.list() |> Enum.sort()
         }}
    end
  end

  defp load_instructions(%Spec{body_ref: {:inline, instructions}}) when is_binary(instructions), do: {:ok, instructions}
  defp load_instructions(%Spec{body_ref: nil}), do: {:ok, ""}

  defp load_instructions(%Spec{name: name, body_ref: {:file, path}}) when is_binary(path) do
    case File.read(path) do
      {:ok, instructions} ->
        {:ok, instructions}

      {:error, reason} ->
        {:error,
         %{
           type: :skill_body_unavailable,
           message: "Could not load skill body for '#{name}'",
           reason: reason
         }}
    end
  end

  defp load_instructions(%Spec{name: name}) do
    {:error,
     %{
       type: :skill_body_unavailable,
       message: "Could not load skill body for '#{name}'",
       reason: :invalid_body_ref
     }}
  end

  defp payload(%Spec{} = spec, instructions, true) do
    spec
    |> payload(instructions, false)
    |> Map.merge(%{
      allowed_tools: spec.allowed_tools,
      tags: spec.tags,
      metadata: spec.metadata || %{},
      license: spec.license,
      compatibility: spec.compatibility,
      vsn: spec.vsn
    })
  end

  defp payload(%Spec{} = spec, instructions, false) do
    %{
      name: spec.name,
      description: spec.description,
      instructions: instructions
    }
  end
end
