Code.require_file("../support/agents/corpus.exs", __DIR__)

defmodule JidoAITest.Authoring.Agents.KnownBugsTest do
  use ExUnit.Case, async: false
  use Mimic
  @moduletag :authoring
  alias Jido.AI.{Authoring, Profile}
  alias JidoAITest.Authoring.{Compiler, Agents.Corpus}

  # Retain finding IDs so the resolved contracts stay linked to BUGS.md.
  @tag bug: "AI-AUTH-001"
  test "AI-AUTH-001: AI wrapper accepts block metadata" do
    Compiler.require_file!(Corpus.fixture("metadata_block.exs"))
    wrapper = JidoAITest.Authoring.Agents.Fixtures.MetadataBlock
    assert apply(wrapper, :definition, []).metadata == %{"owner" => "support"}
    Compiler.require_file!(Corpus.fixture("metadata_core.exs"))
    module = JidoAITest.Authoring.Agents.Fixtures.MetadataCore
    assert apply(module, :definition, []).metadata == %{"owner" => "support"}
  end

  @tag bug: "AI-AUTH-002"
  test "AI-AUTH-002: model shorthand works as a Profile and source data" do
    spec = Corpus.load!(:simple)
    source = hd(spec.profiles) |> Map.delete(:models) |> Map.put(:model, Jido.AI.Test.MockLLM.model())
    assert {:ok, profile} = Profile.new(source)
    assert {:ok, expected} = Authoring.lower(spec.attrs, [profile])
    assert {:ok, ^expected} = Authoring.lower(spec.attrs, [source])
    assert {:ok, document} = Authoring.Codec.encode([source], Corpus.registry(spec))
    assert {:ok, ^expected} = Authoring.Codec.decode(spec.attrs, document, Corpus.registry(spec))
  end

  @tag bug: "AI-AUTH-003"
  test "AI-AUTH-003: keyword profile works through Profile.new and lower" do
    spec = Corpus.load!(:simple)
    source = hd(spec.profiles) |> Map.to_list()
    assert {:ok, profile} = Profile.new(source)
    assert {:ok, expected} = Authoring.lower(spec.attrs, [profile])
    assert {:ok, ^expected} = Authoring.lower(spec.attrs, [source])
    assert {:ok, document} = Authoring.Codec.encode([source], Corpus.registry(spec))
    assert {:ok, ^expected} = Authoring.Codec.decode(spec.attrs, document, Corpus.registry(spec))
  end

  @tag bug: "AI-AUTH-004"
  test "AI-AUTH-004: generated turn ask retains caller context" do
    spec = Corpus.load!(:simple)
    context = %{ai: %{assistant: %{options: [api_key: "local-only", base_url: "http://127.0.0.1:1"]}}}
    # Capture the public call boundary so this bug cannot trigger an external request.
    expect(Jido.AgentServer, :call, fn :test_server, signal, options ->
      assert signal.type == "case.assistant"
      assert signal.data == %{query: "Help"}
      assert options == [timeout: 1234, context: context]
      {:ok, %{state: %{reply: "Ready"}}}
    end)

    assert {:ok, "Ready"} = spec.module.ask(:test_server, "Help", context: context, timeout: 1234)
  end

  @tag bug: "AI-AUTH-005"
  test "AI-AUTH-005: direct Agent.cmd reports that native routes need AgentServer" do
    spec = Corpus.load!(:simple)
    mock = start_supervised!({Jido.AI.Test.MockLLM, script: []})
    context = %{ai: %{assistant: %{options: Jido.AI.Test.MockLLM.options(mock)}}}
    agent = Jido.Agent.instantiate!(Corpus.definition(spec, :map))
    signal = Jido.Signal.new!("case.assistant", %{query: "Help"}, source: "/authoring")
    assert {:error, error} = Jido.Agent.cmd(agent, signal, context: context)

    assert %Jido.AI.Error.Validation.Invalid{field: "runtime"} = error
    assert Exception.message(error) =~ "Native AI routes require AgentServer admission"

    assert Jido.AI.Test.MockLLM.report(mock).requests == []
  end
end
