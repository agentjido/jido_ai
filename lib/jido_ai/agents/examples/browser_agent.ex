defmodule Jido.AI.Examples.BrowserAgent do
  @moduledoc """
  Agent for browsing the web and answering questions about page content (`Jido.AI.Agent`, ReAct strategy implied).

  Manages browser sessions internally per tool call, so the LLM simply
  requests a URL to read without worrying about session lifecycle.

  ## Usage

      {:ok, pid} = Jido.start_agent(MyApp.Jido, Jido.AI.Examples.BrowserAgent)

      {:ok, reply} = Jido.AI.Examples.BrowserAgent.read_page(
        pid,
        "https://hexdocs.pm/elixir/Enum.html"
      )

  ## CLI Usage

      mix jido_ai --agent Jido.AI.Examples.BrowserAgent \\
        "Read https://example.com and summarize it"

  """

  use Jido.AI.Agent,
    name: "browser_agent",
    description: "Web browsing assistant that reads, searches, and summarizes web pages",
    tools: [
      JidoBrowser.Actions.ReadPage,
      JidoBrowser.Actions.SearchWeb,
      JidoBrowser.Actions.SnapshotUrl
    ],
    system_prompt: """
    You are a helpful web browsing assistant. You can search the web, read
    web pages, and answer questions about their content.

    Available tools:
    - read_page: Fetch a URL and return its content as markdown (primary tool for reading pages)
    - search_web: Search the web via Brave Search API and return structured results (titles, URLs, snippets)
    - snapshot_url: Get a page snapshot with links, forms, and headings (use only when you need page structure)

    IMPORTANT RULES:
    - Use read_page as your primary tool for fetching web pages. Call it ONCE per URL.
    - Do NOT re-fetch the same URL. Work with whatever content you received.
    - If content is truncated, answer based on what you have. Do NOT retry with different parameters.
    - Use search_web when the user needs to find something and hasn't provided a URL.
    - Use snapshot_url only when you specifically need form fields, link lists, or heading structure.
    - For follow-up questions, use content from your conversation history. Never re-fetch.

    Always cite specific information from the page when answering questions.
    If the page content is very long, focus on the most relevant sections.
    """,
    max_iterations: 10

  @default_timeout 120_000

  @doc """
  Read a web page and return a summary of its content.

  ## Examples

      {:ok, summary} = BrowserAgent.read_page(pid, "https://example.com")

  """
  @spec read_page(pid(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def read_page(pid, url, opts \\ []) do
    query = "Read #{url} and give me a summary of its content."
    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Summarize a web page's content with a specific focus.

  ## Examples

      {:ok, summary} = BrowserAgent.summarize(pid, "https://example.com", "key features")

  """
  @spec summarize(pid(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def summarize(pid, url, focus \\ "main points", opts \\ []) do
    query = "Read #{url} and summarize it, focusing on: #{focus}"
    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end
end
