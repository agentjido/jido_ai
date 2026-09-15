Code.require_file("../support/agents/corpus.exs", __DIR__)

defmodule JidoAITest.Authoring.Agents.AuthoringTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.Agent.Codec
  alias JidoAITest.Authoring.Agents.Corpus

  for variant <- Corpus.variants(), form <- Corpus.forms() do
    @tag variant: variant, form: form
    test "#{variant}/#{form}: neutral definition, complete state, and codecs", %{variant: variant, form: form} do
      spec = Corpus.load!(variant)
      definition = Corpus.definition(spec, form)
      assert definition === Corpus.definition(spec, :map)
      assert Agent.definition?(definition)
      assert definition.id == nil
      assert definition.state == nil
      assert definition.module == spec.module
      assert definition.metadata == %{"case" => Atom.to_string(variant)}

      profiles = Jido.AI.Agent.profiles(definition)
      assert Map.keys(profiles) |> Enum.sort() == Enum.map(spec.profiles, & &1.id) |> Enum.sort()

      for source <- spec.profiles do
        profile = profiles[source.id]
        assert profile.instructions == "Use the case facts."
        assert profile.controls.timeout == 5_000
        assert profile.result.into == source.result.into
        assert profile.requests.mode == if(variant == :session, do: :session, else: :turn)
      end

      instance = Agent.instantiate!(definition, id: "instance")
      assert instance.state === spec.initial
      assert Agent.definition(instance) === definition
      assert Agent.instantiate!(definition, state: spec.override).state === Map.merge(spec.initial, spec.override)
      assert {:error, _} = Agent.instantiate(definition, state: spec.invalid_state)

      {:ok, document, registry} = Codec.encode(definition)
      assert document === Corpus.agent_document(variant)
      refute Map.has_key?(document, "state")
      refute Map.has_key?(document, "id")

      Enum.reduce(1..3, definition, fn _, current ->
        assert {:ok, ^document} = Codec.encode(current, registry)
        assert {:ok, decoded} = Codec.decode(Jason.decode!(Jason.encode!(document)), registry)
        assert decoded === definition
        decoded
      end)
    end
  end

  for variant <- Corpus.variants() do
    @tag variant: variant
    test "#{variant}: source profile JSON has a stable canonical round trip", %{variant: variant} do
      spec = Corpus.load!(variant)
      registry = Corpus.registry(spec)
      assert {:ok, document} = Jido.AI.Authoring.Codec.encode(spec.profiles, registry)
      assert {:ok, decoded} = Jido.AI.Authoring.Codec.decode(spec.attrs, document, registry)
      assert decoded === Corpus.definition(spec, :source_json)
      assert spec.module.ai_profiles() === Jido.AI.Agent.profiles(decoded)
      assert spec.module.ai_profile(:missing) == nil
    end
  end
end
