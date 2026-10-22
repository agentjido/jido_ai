# This script runs in a new BEAM. No Registry or compiled fixture is sent by the parent.
Application.ensure_all_started(:jido_ai)
ExUnit.start(autorun: false)
Code.require_file("corpus.exs", __DIR__)
alias JidoAITest.Authoring.Agents.Corpus
[url] = System.argv()
{:ok, _} = Jido.start_link(name: :authoring_transport_vm)
spec = Corpus.load!(:tool)
options = [base_url: url, api_key: "local-example-key", max_retries: 0, req_http_options: [retry: false]]

for form <- [:source_json, :agent_json] do
  {:ok, server} = Jido.start_agent(:authoring_transport_vm, Corpus.definition(spec, form))
  signal = Jido.Signal.new!("case.assistant", %{query: "Double four"}, source: "/authoring/vm")

  {:ok, agent} =
    Jido.AI.Test.Requests.call_and_await(server, signal,
      context: %{ai: %{assistant: %{options: options}}},
      timeout: 10_000
    )

  true = agent.state.reply == "Eight"
end

IO.puts("AUTHORING_VM:ok")
