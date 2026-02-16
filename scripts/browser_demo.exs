# Browser Agent Demo
#
# Demonstrates browsing the web with a `Jido.AI.Agent` that reads
# and summarizes web page content using jido_browser.
#
# Run with: mix run scripts/browser_demo.exs
#
# Requires BRAVE_SEARCH_API_KEY in .env (for search_web tool)
#
# Expected behavior:
# - Turn 1: Read Elixir Enum docs and summarize
# - Turn 2: List commonly used functions (from conversation context)
# - Turn 3: Show usage examples (from conversation context)

if Code.ensure_loaded?(Dotenvy) do
  env_file = Path.join(File.cwd!(), ".env")
  if File.exists?(env_file), do: Dotenvy.source!([env_file])
end

alias Jido.AI.Examples.BrowserAgent

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Browser Agent Demo")
IO.puts(String.duplicate("=", 60))

{:ok, _jido} = Jido.start_link(name: BrowserDemo.Jido)
{:ok, pid} = Jido.start_agent(BrowserDemo.Jido, BrowserAgent)

turns = [
  "Read https://hexdocs.pm/elixir/Enum.html and give me a brief summary of the Enum module. Use read_page to fetch it.",
  "What are the most commonly used functions listed?",
  "Show me an example of how to use Enum.map and Enum.filter together"
]

for {message, i} <- Enum.with_index(turns, 1) do
  IO.puts("\n[Turn #{i}] #{message}")
  IO.puts(String.duplicate("-", 60))

  case BrowserAgent.ask_sync(pid, message, timeout: 120_000) do
    {:ok, reply} ->
      IO.puts(reply)

    {:error, reason} ->
      IO.puts("[ERROR] #{inspect(reason)}")
      System.halt(1)
  end
end

GenServer.stop(pid)
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Done - agent browsed the web and answered questions!")
IO.puts(String.duplicate("=", 60) <> "\n")
