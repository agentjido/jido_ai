# The parent supplies only a JSON document. This VM supplies trusted code and values.
{:ok, _} = Application.ensure_all_started(:jido_ai)
ExUnit.start(autorun: false)
Code.require_file("corpus.exs", __DIR__)
alias JidoAITest.Authoring.Agents.Corpus
alias JidoAITest.Authoring.Compiler
alias Jido.Agent.Codec

[url, mode, payload] = System.argv()
module = JidoAITest.Authoring.Agents.Fixtures.Inline
false = Code.ensure_loaded?(module)
Compiler.require_file!(Corpus.fixture("inline.exs"))
definition = apply(module, :definition, [])
profile = apply(module, :ai_profile, [:assistant])
{:ok, %{kind: :action}} = Jido.Executable.resolve(profile.instructions)
[%{target: tool}] = profile.tools
{:ok, %{kind: :action}} = Jido.Executable.resolve(tool)
{:ok, _local_document, registry} = Codec.encode(definition)
document = payload |> Base.decode64!() |> Jason.decode!()

case mode do
  "execute" ->
    {:ok, decoded} = Codec.decode(document, registry)
    true = decoded === definition
    {:ok, _} = Jido.start_link(name: :inline_transport_vm)
    {:ok, server} = Jido.start_agent(:inline_transport_vm, decoded)
    signal = Jido.Signal.new!("case.inline", %{query: "Help"}, source: "/authoring/vm")
    options = [base_url: url, api_key: "local-example-key", max_retries: 0, req_http_options: [retry: false]]

    {:ok, agent} =
      Jido.AgentServer.call(server, signal,
        context: %{tenant: "FRESH", ai: %{assistant: %{options: options}}},
        timeout: 10_000
      )

    true = agent.state === %{reply: "Inline transported", case_id: "case-17", jido_ai_config: %{}}

  "missing_profile" ->
    # Core stores the Profile as a registered value, not embedded executable code.
    entries = Map.reject(registry.entries, fn {_id, {_kind, value}} -> value === profile end)
    true = map_size(entries) < map_size(registry.entries)
    {:error, error} = Codec.decode(document, Jido.Codec.Registry.new!(entries))
    true = is_exception(error)
end

IO.puts("INLINE_VM:#{mode}:ok")
