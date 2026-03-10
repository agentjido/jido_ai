Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Examples.BrowserAgent
alias Jido.AI.Examples.Scripts.Bootstrap

Bootstrap.init!(required_env: ["BRAVE_SEARCH_API_KEY"])
Bootstrap.print_banner("Browser Web Workflow Demo")
Bootstrap.start_named_jido!(BrowserWebWorkflowDemo.Jido)

{:ok, pid} = Jido.start_agent(BrowserWebWorkflowDemo.Jido, BrowserAgent)

turns = [
  "Read https://hexdocs.pm/elixir/Enum.html and summarize the Enum module in two bullets.",
  "From https://hexdocs.pm/elixir/Enum.html, list commonly used Enum functions and explicitly include Enum.map and Enum.filter.",
  "Using https://hexdocs.pm/elixir/Enum.html, show one example that combines Enum.map and Enum.filter in a pipeline."
]

responses =
  for {message, index} <- Enum.with_index(turns, 1) do
    IO.puts("\n[Turn #{index}] #{message}")
    IO.puts(String.duplicate("-", 72))

    case BrowserAgent.ask_sync(pid, message, timeout: 120_000) do
      {:ok, reply} when is_binary(reply) ->
        IO.puts(reply)
        reply

      {:error, reason} ->
        raise "Browser demo failed on turn #{index}: #{inspect(reason)}"
    end
  end

[first_reply, second_reply, third_reply] = responses

Bootstrap.assert!(String.contains?(String.downcase(first_reply), "enum"), "Turn 1 did not summarize Enum content.")
Bootstrap.assert!(String.contains?(String.downcase(second_reply), "map"), "Turn 2 missing Enum.map detail.")
Bootstrap.assert!(String.contains?(String.downcase(second_reply), "filter"), "Turn 2 missing Enum.filter detail.")

Bootstrap.assert!(
  String.contains?(String.downcase(third_reply), "map") and String.contains?(String.downcase(third_reply), "filter"),
  "Turn 3 did not provide a combined map/filter example."
)

GenServer.stop(pid)
IO.puts("\n✓ Browser workflow demo passed semantic checks")
