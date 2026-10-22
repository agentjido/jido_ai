Code.require_file("../support/agents/corpus.exs", __DIR__)

defmodule JidoAITest.Authoring.Agents.SourceVariationsTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.AI.Authoring
  alias Jido.AI.Profile
  alias JidoAITest.Authoring.Agents.Corpus

  for variant <- Corpus.variants() do
    @tag variant: variant
    test "#{variant}: bounded source permutations preserve profiles and reject duplicates", %{variant: variant} do
      spec = Corpus.load!(variant)
      expected = Corpus.definition(spec, :map)

      for reverse? <- [false, true], keyword? <- [false, true] do
        inputs =
          Enum.map(spec.profiles, fn source ->
            pairs = Enum.sort(Map.to_list(source))
            pairs = if reverse?, do: Enum.reverse(pairs), else: pairs
            if keyword?, do: pairs, else: Map.new(pairs)
          end)

        assert {:ok, ^expected} = Authoring.lower(spec.attrs, inputs)
        assert {:ok, ^expected} = Authoring.lower(Map.to_list(spec.attrs), inputs)
      end

      for source <- spec.profiles do
        profile = Profile.new!(source)
        assert {:ok, ^profile} = Profile.new(profile)
        assert {:ok, ^profile} = Profile.new(Map.from_struct(profile))
        assert {:error, _} = Authoring.lower(spec.attrs, [Map.to_list(source) ++ [id: source.id]])
        assert {:error, _} = Authoring.lower(spec.attrs, [Map.put(source, :controls, %{timeout: 0})])
      end
    end
  end

  test "resolved application defaults stay fixed through Codec and explicit empty instructions win" do
    previous = Application.fetch_env(:jido_ai, :agent_defaults)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:jido_ai, :agent_defaults, value)
        :error -> Application.delete_env(:jido_ai, :agent_defaults)
      end
    end)

    spec = Corpus.load!(:simple)
    Application.put_env(:jido_ai, :agent_defaults, %{model: "openai:gpt-4o-mini", instructions: "First default"})
    source = %{id: :assistant, result: %{into: :reply}}
    assert {:ok, definition} = Authoring.lower(spec.attrs, [source])
    assert Jido.AI.Agent.profile(definition, :assistant).instructions == "First default"
    assert {:ok, explicit} = Authoring.lower(spec.attrs, [Map.put(source, :instructions, "")])
    assert Jido.AI.Agent.profile(explicit, :assistant).instructions == ""
    assert {:ok, document, registry} = Jido.Agent.Codec.encode(definition)
    Application.put_env(:jido_ai, :agent_defaults, %{model: "openai:gpt-4o", instructions: "Second default"})
    assert {:ok, ^definition} = Jido.Agent.Codec.decode(document, registry)
    assert {:ok, later} = Authoring.lower(spec.attrs, [source])
    assert Jido.AI.Agent.profile(later, :assistant).instructions == "Second default"
  end

  test "Agent and profile metadata preserve atom, string, mixed, false and empty values through Codec" do
    spec = Corpus.load!(:simple)

    for {metadata, normalized} <- [
          {%{}, %{}},
          {%{owner: "test"}, %{"owner" => "test"}},
          {%{"owner" => "test"}, %{"owner" => "test"}},
          {%{"labels" => [], owner: false, nested: %{empty: ""}},
           %{"labels" => [], "owner" => false, "nested" => %{"empty" => ""}}}
        ] do
      profiles = Enum.map(spec.profiles, &Map.put(&1, :metadata, metadata))
      assert {:ok, definition} = Authoring.lower(%{spec.attrs | metadata: metadata}, profiles)
      assert {:ok, doc, registry} = Jido.Agent.Codec.encode(definition)
      assert {:ok, decoded} = Jido.Agent.Codec.decode(Jason.decode!(Jason.encode!(doc)), registry)
      assert decoded === definition
      assert decoded.metadata === metadata
      assert Jido.AI.Agent.profile(decoded, :assistant).metadata === normalized
    end
  end
end
