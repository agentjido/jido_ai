Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Examples.Scripts.Bootstrap
alias Jido.AI.Examples.Tools.Browser.{ReadPage, SearchWeb, SnapshotUrl}

Bootstrap.init!(required_env: ["BRAVE_SEARCH_API_KEY"])
Bootstrap.print_banner("Browser Adapter Compatibility Smoke Demo")

url = "https://example.com"

extract_with_fallback = fn session ->
  [:html, :text]
  |> Enum.reduce_while({:error, :no_content}, fn format, _acc ->
    case JidoBrowser.extract_content(session, format: format, selector: "body") do
      {:ok, _session, %{content: content}} when is_binary(content) and byte_size(content) > 0 ->
        {:halt, {:ok, content, format}}

      _ ->
        {:cont, {:error, format}}
    end
  end)
end

case JidoBrowser.start_session(headless: true) do
  {:ok, session} ->
    try do
      {:ok, session, _} = JidoBrowser.navigate(session, url)
      {:ok, content, format} = extract_with_fallback.(session)
      Bootstrap.assert!(String.length(content) > 20, "Vibium adapter extraction returned empty content.")
      IO.puts("✓ Vibium adapter extraction OK (#{format}, #{String.length(content)} chars)")
    after
      JidoBrowser.end_session(session)
    end

  {:error, reason} ->
    raise "Failed to start Vibium adapter session: #{inspect(reason)}"
end

case JidoBrowser.start_session(adapter: JidoBrowser.Adapters.Web) do
  {:ok, session} ->
    try do
      {:ok, session, _} = JidoBrowser.navigate(session, url)
      {:ok, content, format} = extract_with_fallback.(session)
      Bootstrap.assert!(String.length(content) > 20, "Web adapter extraction returned empty content.")
      IO.puts("✓ Web adapter extraction OK (#{format}, #{String.length(content)} chars)")
    after
      JidoBrowser.end_session(session)
    end

  {:error, reason} ->
    IO.puts("⚠ Web adapter unavailable, skipping Web extraction check: #{inspect(reason)}")
end

{:ok, read_page} = ReadPage.run(%{url: url}, %{})
Bootstrap.assert!(String.length(read_page.content) > 20, "read_page returned too little content.")

{:ok, search} = SearchWeb.run(%{query: "elixir programming language", max_results: 3}, %{})
Bootstrap.assert!(search.count > 0, "search_web returned no results.")

{:ok, snapshot} = SnapshotUrl.run(%{url: url, include_links: true, include_headings: true}, %{})
Bootstrap.assert!(is_binary(snapshot.title), "snapshot_url did not return a title.")

IO.puts("✓ Wrapper actions read_page/search_web/snapshot_url passed")
