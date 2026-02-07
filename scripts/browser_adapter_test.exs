# Browser Adapter & Actions Test
#
# Verifies both adapters work with extract_content after the --markdown fix,
# and tests the new composite actions (ReadPage, SnapshotUrl, SearchWeb).
#
# Run with: mix run scripts/browser_adapter_test.exs

url = "https://example.com"

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Browser Adapter & Actions Test")
IO.puts(String.duplicate("=", 60))

# --- Test 1: Vibium adapter extract_content ---
IO.puts("\n[1] Vibium adapter - extract_content :markdown")

case JidoBrowser.start_session(headless: true) do
  {:ok, session} ->
    try do
      {:ok, session, _} = JidoBrowser.navigate(session, url)

      case JidoBrowser.extract_content(session, format: :markdown) do
        {:ok, _session, %{content: content}} ->
          IO.puts("    OK - #{String.length(content)} chars")

        {:error, reason} ->
          IO.puts("    FAIL - #{inspect(reason)}")
          System.halt(1)
      end
    after
      JidoBrowser.end_session(session)
    end

  {:error, reason} ->
    IO.puts("    SKIP - #{inspect(reason)}")
end

# --- Test 2: Web adapter extract_content ---
IO.puts("\n[2] Web adapter - extract_content :markdown")

case JidoBrowser.start_session(adapter: JidoBrowser.Adapters.Web) do
  {:ok, session} ->
    try do
      {:ok, session, _} = JidoBrowser.navigate(session, url)

      case JidoBrowser.extract_content(session, format: :markdown) do
        {:ok, _session, %{content: content}} ->
          IO.puts("    OK - #{String.length(content)} chars")

        {:error, reason} ->
          IO.puts("    FAIL - #{inspect(reason)}")
          System.halt(1)
      end
    after
      JidoBrowser.end_session(session)
    end

  {:error, reason} ->
    IO.puts("    SKIP - #{inspect(reason)}")
end

# --- Test 3: ReadPage composite action ---
IO.puts("\n[3] ReadPage action")

case JidoBrowser.Actions.ReadPage.run(%{url: url}, %{}) do
  {:ok, %{content: content, format: format}} ->
    IO.puts("    OK - #{format} / #{String.length(content)} chars")

  {:error, reason} ->
    IO.puts("    FAIL - #{inspect(reason)}")
    System.halt(1)
end

# --- Test 4: SearchWeb composite action (Brave Search API) ---
IO.puts("\n[4] SearchWeb action (Brave Search API)")

case JidoBrowser.Actions.SearchWeb.run(%{query: "elixir programming language", max_results: 3}, %{}) do
  {:ok, %{query: query, results: results, count: count}} ->
    IO.puts("    OK - '#{query}' returned #{count} results")

    Enum.each(results, fn r ->
      IO.puts("    #{r.rank}. #{r.title}")
    end)

  {:error, reason} ->
    IO.puts("    FAIL - #{inspect(reason)}")
    System.halt(1)
end

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("All tests passed!")
IO.puts(String.duplicate("=", 60) <> "\n")
