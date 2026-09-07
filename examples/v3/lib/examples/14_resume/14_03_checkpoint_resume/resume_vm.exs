alias Jido.AI.Reasoning.ReAct
alias JidoAI.Examples.StandaloneAuthoring.Add
alias JidoAI.Examples.MockLLM

[token_path, base_url] = System.argv()
true = URI.parse(base_url).host == "127.0.0.1"
{:ok, _} = Application.ensure_all_started(:jido_ai_v3_examples)

# Safe ETF decoding can use only atoms already known in this VM. Load the
# declared application code before reading a trusted signed checkpoint.
for app <- [:jido_ai_v3_examples, :jido_ai, :req_llm, :zoi] do
  {:ok, modules} = :application.get_key(app, :modules)
  :ok = Code.ensure_all_loaded(modules)
end

{:ok, _} = Jido.start_link(name: :checkpoint_resume_vm)

config =
  ReAct.Config.new(
    model: MockLLM.model(),
    tools: [Add],
    streaming: false,
    token_secret: "checkpoint-resume-fixture",
    llm_opts: [
      base_url: base_url,
      api_key: "local-example-key",
      max_retries: 0,
      req_http_options: [retry: false, receive_timeout: 5_000],
      receive_timeout: 5_000
    ]
  )

{:ok, resumed} =
  ReAct.continue(File.read!(token_path), config,
    context: %{jido: :checkpoint_resume_vm, observer: self()},
    limits: %{timeout: 5_000, max_tool_calls: 32}
  )

result = ReAct.collect_stream(resumed.events)

receive do
  {:standalone_add, _, _, _} -> raise "A completed tool ran again in the fresh VM"
after
  0 -> :ok
end

IO.puts(
  "CHECKPOINT_VM:" <>
    Jason.encode!(%{
      result: result.result,
      usage: result.usage,
      termination_reason: result.termination_reason,
      kinds: Enum.map(result.trace, & &1.kind)
    })
)
