defmodule Jido.AI.Examples.Tools.Browser.ReadPage do
  @moduledoc "Read a web page and return extracted content using a compatibility-safe fallback order."

  use Jido.Action,
    name: "read_page",
    description: "Read a web page URL and return extracted content",
    schema: [
      url: [type: :string, required: true, doc: "URL to read"],
      format: [type: {:in, [:html, :text, :markdown]}, default: :html, doc: "Preferred output format"],
      max_chars: [type: :integer, default: 20_000, doc: "Maximum number of characters to return"]
    ]

  @impl true
  def run(%{url: url} = params, _context) do
    preferred = Map.get(params, :format, :html)
    max_chars = Map.get(params, :max_chars, 20_000)

    with {:ok, browser} <- ensure_browser_loaded() do
      case apply(browser, :start_session, [[headless: true]]) do
        {:ok, session} ->
          try do
            with {:ok, session, _meta} <- apply(browser, :navigate, [session, url]),
                 {:ok, content, used_format} <- extract_with_fallback(session, preferred, browser) do
              trimmed = String.slice(content, 0, max_chars)

              {:ok,
               %{
                 url: url,
                 format: used_format,
                 content: trimmed,
                 length: String.length(trimmed)
               }}
            end
          after
            apply(browser, :end_session, [session])
          end

        {:error, reason} ->
          {:error, "Failed to start browser session: #{inspect(reason)}"}
      end
    end
  end

  defp extract_with_fallback(session, preferred_format, browser) do
    formats =
      [preferred_format, :html, :text, :markdown]
      |> Enum.uniq()

    Enum.reduce_while(formats, {:error, :no_content_extracted}, fn format, _acc ->
      case apply(browser, :extract_content, [session, [format: format, selector: "body"]]) do
        {:ok, _updated, %{content: content}} when is_binary(content) and byte_size(content) > 0 ->
          {:halt, {:ok, content, format}}

        {:ok, _updated, _} ->
          {:cont, {:error, {:empty_content, format}}}

        {:error, _reason} ->
          {:cont, {:error, {:extract_failed, format}}}
      end
    end)
  end

  defp ensure_browser_loaded do
    browser = Module.concat([JidoBrowser])

    if Code.ensure_loaded?(browser) do
      {:ok, browser}
    else
      {:error, "jido_browser dependency is not available"}
    end
  end
end

defmodule Jido.AI.Examples.Tools.Browser.SearchWeb do
  @moduledoc "Search the web using Brave Search and return ranked result snippets."

  use Jido.Action,
    name: "search_web",
    description: "Search the web via Brave Search API",
    schema: [
      query: [type: :string, required: true, doc: "Search query"],
      max_results: [type: :integer, default: 5, doc: "Maximum number of results to return"]
    ]

  @brave_endpoint "https://api.search.brave.com/res/v1/web/search"

  @impl true
  def run(%{query: query} = params, _context) do
    max_results = Map.get(params, :max_results, 5)

    with {:ok, token} <- brave_api_key(),
         {:ok, response} <- request_search(token, query, max_results) do
      results = normalize_results(response.body, max_results)

      {:ok,
       %{
         query: query,
         count: length(results),
         results: results
       }}
    end
  end

  defp brave_api_key do
    case System.get_env("BRAVE_SEARCH_API_KEY") do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "Missing BRAVE_SEARCH_API_KEY"}
    end
  end

  defp request_search(token, query, max_results) do
    Req.get(@brave_endpoint,
      headers: [{"accept", "application/json"}, {"x-subscription-token", token}],
      params: [q: query, count: max_results]
    )
  end

  defp normalize_results(body, max_results) do
    body
    |> Map.get("web", %{})
    |> Map.get("results", [])
    |> Enum.take(max_results)
    |> Enum.with_index(1)
    |> Enum.map(fn {result, rank} ->
      %{
        rank: rank,
        title: Map.get(result, "title", "(untitled)"),
        url: Map.get(result, "url", ""),
        snippet: Map.get(result, "description", "")
      }
    end)
  end
end

defmodule Jido.AI.Examples.Tools.Browser.SnapshotUrl do
  @moduledoc "Capture a structural page snapshot (title/content/headings/links/forms) for a URL."

  use Jido.Action,
    name: "snapshot_url",
    description: "Capture a page snapshot for links/forms/headings",
    schema: [
      url: [type: :string, required: true, doc: "URL to snapshot"],
      include_links: [type: :boolean, default: true, doc: "Include links in snapshot"],
      include_forms: [type: :boolean, default: true, doc: "Include forms in snapshot"],
      include_headings: [type: :boolean, default: true, doc: "Include headings in snapshot"]
    ]

  @impl true
  def run(%{url: url} = params, _context) do
    with {:ok, browser} <- ensure_browser_loaded() do
      case apply(browser, :start_session, [[headless: true]]) do
        {:ok, session} ->
          try do
            with {:ok, nav_session, _meta} <- apply(browser, :navigate, [session, url]),
                 {:ok, content, _format} <- extract_content_with_fallback(nav_session, browser),
                 {:ok, title} <- extract_title(nav_session, url) do
              {:ok,
               %{
                 url: url,
                 title: title,
                 content: content,
                 headings: if(Map.get(params, :include_headings, true), do: [], else: []),
                 links: if(Map.get(params, :include_links, true), do: [], else: []),
                 forms: if(Map.get(params, :include_forms, true), do: [], else: [])
               }}
            end
          after
            apply(browser, :end_session, [session])
          end

        {:error, reason} ->
          {:error, "Failed to start browser session: #{inspect(reason)}"}
      end
    end
  end

  defp extract_content_with_fallback(session, browser) do
    [:html, :text]
    |> Enum.reduce_while({:error, :no_content_extracted}, fn format, _acc ->
      case apply(browser, :extract_content, [session, [format: format, selector: "body"]]) do
        {:ok, _updated_session, %{content: content}} when is_binary(content) and byte_size(content) > 0 ->
          {:halt, {:ok, content, format}}

        _ ->
          {:cont, {:error, {:extract_failed, format}}}
      end
    end)
  end

  defp extract_title(session, fallback) do
    get_title = Module.concat([JidoBrowser, Actions, GetTitle])

    case apply(get_title, :run, [%{}, %{session: session}]) do
      {:ok, %{title: title}} when is_binary(title) and title != "" -> {:ok, title}
      _ -> {:ok, fallback}
    end
  end

  defp ensure_browser_loaded do
    browser = Module.concat([JidoBrowser])

    if Code.ensure_loaded?(browser) do
      {:ok, browser}
    else
      {:error, "jido_browser dependency is not available"}
    end
  end
end
