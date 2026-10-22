Code.require_file("../support/agents/corpus.exs", __DIR__)

defmodule JidoAITest.Authoring.Agents.TransportTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.AI.Test.MockLLM
  alias JidoAITest.Authoring.Agents.Corpus

  for format <- [:map, :json, :yaml] do
    @tag format: format
    test "public #{format} Agent import executes with caller context", %{format: format} do
      spec = Corpus.load!(:simple)
      # Public portable model IDs are distinct from core Codec registered model records.
      profiles = Enum.map(spec.profiles, &Map.put(&1, :models, %{default: %{model: "openai:gpt-4o-mini"}}))
      {:ok, original} = Jido.AI.Authoring.lower(spec.attrs, profiles)
      registries = %{schemas: %{"domain" => original.schema}}
      assert {:ok, document} = Jido.AI.export(original, format, registries: registries)
      assert {:ok, imported} = Jido.AI.import(document, registries: registries)
      jido = :"authoring_transport_#{System.unique_integer([:positive])}"
      start_supervised!({Jido, name: jido})
      mock = start_supervised!({MockLLM, script: [%{reply: {:text, "Imported"}}]})
      {:ok, server} = Jido.start_agent(jido, imported)
      signal = Jido.Signal.new!("case.assistant", %{query: "Help"}, source: "/authoring")

      assert {:ok, agent} =
               Jido.AI.Test.Requests.call_and_await(server, signal,
                 context: %{ai: %{assistant: %{options: MockLLM.options(mock)}}},
                 timeout: 10_000
               )

      assert Map.delete(agent.state, :requests) === Map.delete(%{spec.initial | reply: "Imported"}, :requests)
      assert %{remaining: [], unexpected: [], requests: [request]} = MockLLM.report(mock)
      assert request.body["model"] == "gpt-4o-mini"

      assert Enum.any?(
               request.body["input"],
               &(&1 == %{"role" => "system", "content" => [%{"type" => "input_text", "text" => "Use the case facts."}]})
             )
    end
  end

  for mode <- ["execute", "missing_profile"] do
    @tag timeout: 60_000, coverage_external_vm: true, mode: mode
    test "separate BEAM inline transport: #{mode}", %{mode: mode} do
      JidoAITest.Authoring.Compiler.require_file!(Corpus.fixture("inline.exs"))
      module = JidoAITest.Authoring.Agents.Fixtures.Inline
      {:ok, document, _parent_registry} = Jido.Agent.Codec.encode(apply(module, :definition, []))

      script =
        if mode == "execute" do
          [
            %{reply: {:tools, [%{id: "inline-vm", name: "echo", arguments: %{value: "from another VM"}}]}},
            %{reply: {:text, "Inline transported"}}
          ]
        else
          []
        end

      mock = start_supervised!({MockLLM, script: script})
      paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])
      consumer = Path.expand("../support/agents/inline_transport_vm.exs", __DIR__)
      # Only JSON data crosses from the parent. No Registry or BEAM binaries do.
      payload = document |> Jason.encode!() |> Base.encode64()

      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          ["--erl", "+S 2:2"] ++ paths ++ [consumer, MockLLM.options(mock)[:base_url], mode, payload],
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert output =~ "INLINE_VM:#{mode}:ok"
      assert %{remaining: [], unexpected: [], requests: requests} = MockLLM.report(mock)

      if mode == "execute" do
        assert [first, last] = requests
        assert [%{"function" => %{"name" => "echo"}}] = first.body["tools"]

        assert Enum.all?(requests, fn request ->
                 Enum.any?(
                   request.body["messages"],
                   &(&1["role"] == "system" and &1["content"] == "Tenant FRESH: Help")
                 )
               end)

        assert Enum.any?(
                 last.body["messages"],
                 &(&1["role"] == "tool" and &1["tool_call_id"] == "inline-vm" and
                     String.contains?(&1["content"], "from another VM"))
               )
      else
        assert requests == []
      end
    end
  end

  @tag timeout: 60_000
  @tag :coverage_external_vm
  test "a separate BEAM decodes checked-in source and Agent JSON with its own Registry and runs tools" do
    mock =
      start_supervised!(
        {MockLLM,
         script:
           List.flatten(
             List.duplicate(
               [
                 %{reply: {:tools, [%{id: "fresh-tool", name: "double", arguments: %{value: 4}}]}},
                 %{reply: {:text, "Eight"}}
               ],
               2
             )
           )}
      )

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])
    script = Path.expand("../support/agents/transport_vm.exs", __DIR__)

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++ paths ++ [script, MockLLM.options(mock)[:base_url]],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "AUTHORING_VM:ok"
    assert %{remaining: [], unexpected: [], requests: requests} = MockLLM.report(mock)
    assert length(requests) == 4

    assert Enum.count(requests, fn request ->
             Enum.any?(request.body["messages"], &(&1["role"] == "tool" and String.contains?(&1["content"], "8")))
           end) == 2
  end
end
