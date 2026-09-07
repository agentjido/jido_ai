defmodule Jido.AI.Skill.Runtime do
  @moduledoc false
  alias Jido.AI.Actions.Skill.{LoadResource, LoadSkill}
  alias Jido.AI.Skill.{Registry, ResourceProvider, Resources}

  def reserved_keys do
    [
      LoadSkill.context_skills_key(),
      ResourceProvider.context_provider_key(),
      Resources.context_policy_key()
    ]
  end

  def request_options(resources) do
    context = Map.get(resources, :tool_context, %{})
    keys = reserved_keys()

    if is_map(context) and
         Enum.any?(
           keys,
           &(Map.has_key?(context, &1) or Map.has_key?(context, Atom.to_string(&1)))
         ) do
      Jido.AI.Profile.error(
        "tool_context",
        "Bind the skill catalog, provider and policy in host context"
      )
    else
      :ok
    end
  end

  def bind(context, profile, owner) do
    if Enum.any?(profile.tools, &(&1.target in [LoadSkill, LoadResource])) do
      binding = Map.take(context, reserved_keys() ++ Enum.map(reserved_keys(), &Atom.to_string/1))
      revision = :crypto.hash(:sha256, :erlang.term_to_binary(binding))
      session = {:jido_ai_skills, owner, profile.id, revision}

      with :ok <- Registry.own_session(session, owner),
           do: {:ok, Map.put(context, :jido_ai_skill_session, session)}
    else
      {:ok, Map.delete(context, :jido_ai_skill_session)}
    end
  end

  def refs(
        %{name: "load_skill", tool: %{target: LoadSkill}},
        {:ok, original, _},
        {:ok, approved, _}
      )
      when is_map(original) and is_map(approved) do
    name = field(approved, :name)

    if is_binary(name) and name == field(original, :name) and
         is_binary(field(original, :instructions)) and is_binary(field(approved, :instructions)),
       do: %{durable: true, kind: :skill_activation, skill_name: name},
       else: %{}
  end

  def refs(_, _, _), do: %{}

  def untrusted_refs(refs) when is_map(refs) do
    refs = Map.drop(refs, [:durable, :skill_name, "durable", "skill_name"])

    if field(refs, :kind) in [:skill_activation, "skill_activation"],
      do: Map.drop(refs, [:kind, "kind"]),
      else: refs
  end

  def untrusted_refs(_), do: %{}
  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
