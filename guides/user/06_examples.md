# Common Recipes and Examples

This guide provides practical examples and patterns for common use cases with Jido.AI.

## Table of Contents

1. [Customer Support Agent](#customer-support-agent)
2. [Data Analysis Agent](#data-analysis-agent)
3. [Code Review Agent](#code-review-agent)
4. [Research Assistant](#research-assistant)
5. [Content Generator](#content-generator)
6. [Multi-Agent Workflow](#multi-agent-workflow)

---

## Customer Support Agent

An agent that answers customer questions and can look up order information.

```elixir
defmodule CustomerSupportAgent do
  @moduledoc """
  Customer support agent with order lookup capabilities.
  """

  use Jido.Agent,
    name: "support_agent",
    strategy: {
      Jido.AI.Strategies.ReAct,
      model: "anthropic:claude-sonnet-4-20250514",
      tools: [
        LookupOrder,
        CheckRefundStatus,
        GetShippingInfo,
        CreateSupportTicket
      ],
      max_iterations: 10
    }

  @impl true
  def system_prompt do
    """
    You are a helpful customer support assistant for an e-commerce store.

    Your capabilities:
    - Look up order status by order ID or email
    - Check refund status
    - Provide shipping information
    - Create support tickets for complex issues

    Guidelines:
    - Always be empathetic and professional
    - Ask for order ID or email when needed
    - If you can't resolve an issue, offer to create a ticket
    - Never make up information - use the tools to get facts
    """
  end
end

# Action: Order Lookup
defmodule LookupOrder do
  use Jido.Action

  @impl true
  def name, do: "lookup_order"

  @impl true
  def description, do: """
  Look up an order by order ID or customer email.
  Returns order status, items, and tracking information.
  """

  @impl true
  def schema do
    [
      identifier: [
        type: :string,
        required: true,
        doc: "Order ID (e.g., 'ORD-12345') or customer email"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    id = params["identifier"]

    # Query your database
    case Orders.get_by_identifier(id) do
      nil ->
        {:error, "No order found with identifier: #{id}"}

      order ->
        {:ok, %{
          order_id: order.id,
          status: order.status,
          items: order.items,
          total: order.total,
          tracking: order.tracking_number,
          estimated_delivery: order.estimated_delivery
        }}
    end
  end
end

# Usage
{:ok, agent} = CustomerSupportAgent.start_link()

CustomerSupportAgent.chat(agent, """
  Where is my order ORD-12345?
""")

CustomerSupportAgent.chat(agent, """
  I ordered last week but haven't received a shipping confirmation.
  My email is user@example.com
""")
```

---

## Data Analysis Agent

An agent that can analyze data and create reports.

```elixir
defmodule DataAnalysisAgent do
  @moduledoc """
  Agent for analyzing data and generating insights.
  """

  use Jido.Agent,
    name: "analyst",
    strategy: {
      Jido.AI.Strategies.ReAct,
      model: "anthropic:claude-sonnet-4-20250514",
      tools: [
        QueryDatabase,
        CalculateStatistics,
        GenerateChart,
        ExportCSV
      ],
      max_iterations: 15
    }

  @impl true
  def system_prompt do
    """
    You are a data analyst. Help users understand their data through:
    - Querying and filtering data
    - Calculating statistics (mean, median, trends)
    - Creating visualizations
    - Exporting results

    Always explain your findings clearly and suggest next steps.
    """
  end
end

# Action: Query Database
defmodule QueryDatabase do
  use Jido.Action

  @impl true
  def name, do: "query_database"

  @impl true
  def description, do: """
  Execute SQL queries on the database.
  Use for filtering, aggregating, and joining data.
  """

  @impl true
  def schema do
    [
      query: [
        type: :string,
        required: true,
        doc: "SQL query to execute (SELECT only)"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    query = params["query"]

    # Security: Only allow SELECT queries
    unless String.starts_with?(String.upcase(String.trim(query)), "SELECT") do
      {:error, "Only SELECT queries are allowed"}
    else
      case Repo.query(query) do
        {:ok, %{rows: rows, columns: columns}} ->
          {:ok, %{
            columns: columns,
            rows: rows,
            row_count: length(rows)
          }}

        {:error, reason} ->
          {:error, "Query failed: #{inspect(reason)}"}
      end
    end
  end
end

# Action: Calculate Statistics
defmodule CalculateStatistics do
  use Jido.Action

  @impl true
  def name, do: "calculate_stats"

  @impl true
  def description, do: """
  Calculate statistics on a list of numbers.
  Provides mean, median, mode, standard deviation, min, max.
  """

  @impl true
  def schema do
    [
      values: [
        type: {:list, :number},
        required: true,
        doc: "List of numbers to analyze"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    values = params["values"]

    sorted = Enum.sort(values)
    count = length(values)
    sum = Enum.sum(values)
    mean = sum / count

    median = if rem(count, 2) == 0 do
      mid = div(count, 2)
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    else
      Enum.at(sorted, div(count, 2))
    end

    variance = Enum.reduce(values, 0, fn v, acc ->
      acc + :math.pow(v - mean, 2)
    end) / count

    std_dev = :math.sqrt(variance)

    {:ok, %{
      count: count,
      mean: Float.round(mean, 2),
      median: median,
      min: Enum.min(sorted),
      max: Enum.max(sorted),
      std_dev: Float.round(std_dev, 2)
    }}
  end
end

# Usage
{:ok, agent} = DataAnalysisAgent.start_link()

DataAnalysisAgent.chat(agent, """
  What's the average order value for this month?
""")

DataAnalysisAgent.chat(agent, """
  Compare sales between January and February.
  Which month performed better?
""")
```

---

## Code Review Agent

An agent that reviews code for bugs, style issues, and best practices.

```elixir
defmodule CodeReviewAgent do
  @moduledoc """
  Automated code review agent.
  """

  use Jido.Agent,
    name: "code_reviewer",
    strategy: {
      Jido.AI.Strategies.ChainOfThought,
      model: "anthropic:claude-sonnet-4-20250514"
    }

  @impl true
  def system_prompt do
    """
    You are a code reviewer. Analyze code for:

    1. **Correctness**: Bugs, edge cases, error handling
    2. **Security**: SQL injection, XSS, authentication issues
    3. **Performance**: Inefficient algorithms, N+1 queries
    4. **Style**: Naming, formatting, complexity
    5. **Best Practices**: Language idioms, patterns

    Format your review as:
    - Summary
    - Issues (with severity: Critical/High/Medium/Low)
    - Suggestions
    - Positive observations
    """
  end

  @impl true
  def review(code, language \\ "elixir") do
    chat(%{}, """
    Review this #{language} code:

    ```#{language}
    #{code}
    ```
    """)
  end
end

# Usage
code = """
defmodule User do
  def authenticate(email, password) do
    query = "SELECT * FROM users WHERE email = '#{email}'"
    user = Repo.query!(query)

    if user.password == password do
      {:ok, user}
    else
      :error
    end
  end
end
"""

{:ok, agent} = CodeReviewAgent.start_link()
CodeReviewAgent.review(agent, code)

# Response highlights SQL injection vulnerability
```

---

## Research Assistant

An agent that can search the web and synthesize information.

```elixir
defmodule ResearchAssistant do
  @moduledoc """
  Research assistant with web search and synthesis capabilities.
  """

  use Jido.Agent,
    name: "researcher",
    strategy: {
      Jido.AI.Strategies.ReAct,
      model: "anthropic:claude-sonnet-4-20250514",
      tools: [
        WebSearch,
        WebPageExtract,
        Summarize,
        CiteSources
      ],
      max_iterations: 20
    }

  @impl true
  def system_prompt do
    """
    You are a research assistant. When researching a topic:

    1. Search for reliable sources
    2. Extract key information from multiple sources
    3. Synthesize findings into a coherent summary
    4. Always cite your sources

    Prioritize:
    - Academic sources
    - Official documentation
    - Reputable news outlets
    - Industry experts

    Be thorough but concise.
    """
  end
end

# Action: Web Search
defmodule WebSearch do
  use Jido.Action

  @impl true
  def name, do: "web_search"

  @impl true
  def description, do: """
  Search the web for information.
  Returns top results with titles, snippets, and URLs.
  """

  @impl true
  def schema do
    [
      query: [
        type: :string,
        required: true,
        doc: "Search query"
      ],
      num_results: [
        type: :integer,
        default: 10,
        doc: "Number of results to return"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    query = params["query"]
    num = params["num_results"]

    # Call search API
    case SearchAPI.search(query, num) do
      {:ok, results} ->
        {:ok, %{
          query: query,
          results: Enum.map(results, fn r ->
            %{
              title: r.title,
              url: r.url,
              snippet: r.snippet,
              published_date: r.date
            }
          end)
        }}

      {:error, _} ->
        {:error, "Search failed"}
    end
  end
end

# Action: Extract Web Page
defmodule WebPageExtract do
  use Jido.Action

  @impl true
  def name, do: "extract_page"

  @impl true
  def description, do: """
  Extract the main content from a web page.
  Removes navigation, ads, and other clutter.
  """

  @impl true
  def schema do
    [
      url: [
        type: :string,
        required: true,
        doc: "URL of the page to extract"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    url = params["url"]

    case ContentExtractor.extract(url) do
      {:ok, content} ->
        {:ok, %{
          url: url,
          title: content.title,
          content: String.slice(content.text, 0, 10_000),
          word_count: content.word_count
        }}

      {:error, _} ->
        {:error, "Failed to extract page"}
    end
  end
end

# Usage
{:ok, agent} = ResearchAssistant.start_link()

ResearchAssistant.chat(agent, """
  Research the latest developments in quantum computing.
  Focus on practical applications from 2024.
""")

ResearchAssistant.chat(agent, """
  What are the pros and cons of different battery technologies
  for electric vehicles?
""")
```

---

## Content Generator

An agent that generates marketing copy, blog posts, and other content.

```elixir
defmodule ContentGenerator do
  @moduledoc """
  Content generation agent with Tree-of-Thoughts for creativity.
  """

  use Jido.Agent,
    name: "content_gen",
    strategy: {
      Jido.AI.Strategies.TreeOfThoughts,
      model: "anthropic:claude-sonnet-4-20250514",
      max_depth: 3,
      branches: 5
    }

  @impl true
  def system_prompt do
    """
    You are a creative content writer. Generate engaging content that is:
    - Clear and concise
    - Tailored to the audience
    - Optimized for the intended platform
    - Compelling and action-oriented

    Consider multiple angles and pick the most effective approach.
    """
  end

  @impl true
  def generate(agent, type, topic, opts \\ []) do
    audience = Keyword.get(opts, :audience, "general")
    tone = Keyword.get(opts, :tone, "professional")
    length = Keyword.get(opts, :length, "medium")

    chat(agent, """
    Generate #{type} about: #{topic}

    Audience: #{audience}
    Tone: #{tone}
    Length: #{length}

    Make it engaging and effective.
    """)
  end
end

# Usage
{:ok, agent} = ContentGenerator.start_link()

# Blog post
ContentGenerator.generate(agent, "blog post", "remote work productivity",
  audience: "managers",
  tone: "informative"
)

# Marketing email
ContentGenerator.generate(agent, "marketing email", "new product launch",
  audience: "existing customers",
  tone: "exciting"
)

# Social media
ContentGenerator.generate(agent, "tweet thread", "AI tips",
  audience: "developers",
  tone: "casual"
)
```

---

## Multi-Agent Workflow

Coordinate multiple specialized agents for complex tasks.

```elixir
defmodule MultiAgentCoordinator do
  @moduledoc """
  Coordinates multiple specialized agents.
  """

  use Jido.Agent,
    name: "coordinator",
    strategy: {
      Jido.AI.Strategies.ReAct,
      model: "anthropic:claude-sonnet-4-20250514",
      tools: [
        DelegateToResearcher,
        DelegateToCoder,
        DelegateToReviewer,
        CompileResults
      ],
      max_iterations: 15
    }

  @impl true
  def system_prompt do
    """
    You are a project coordinator. You have access to specialist agents:
    - Researcher: Gathers information
    - Coder: Writes and implements code
    - Reviewer: Reviews and validates work

    Break down tasks and delegate to the appropriate specialist.
    Compile their outputs into a final result.
    """
  end
end

# Action: Delegate to Researcher
defmodule DelegateToResearcher do
  use Jido.Action

  @impl true
  def name, do: "delegate_research"

  @impl true
  def description, do: "Delegate a research task to the research agent"

  @impl true
  def schema do
    [
      task: [
        type: :string,
        required: true,
        doc: "Research task description"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    # Get or start the researcher agent
    {:ok, researcher} = get_or_start_researcher()

    # Send the task
    case Researcher.chat(researcher, params["task"]) do
      {:ok, response} ->
        {:ok, %{research_findings: response.answer}}

      {:error, reason} ->
        {:error, "Research failed: #{reason}"}
    end
  end

  defp get_or_start_researcher do
    case Process.whereis(:researcher) do
      nil -> ResearchAgent.start_link(name: :researcher)
      pid -> {:ok, pid}
    end
  end
end

# Similar for Coder and Reviewer...

# Usage
{:ok, coordinator} = MultiAgentCoordinator.start_link()

MultiAgentCoordinator.chat(coordinator, """
  Build a simple web scraper for a news site.
  Research the best approach, implement it, and review the code.
""")

# Flow:
# 1. Coordinator asks Researcher about best scraping libraries
# 2. Coordinator asks Coder to implement the scraper
# 3. Coordinator asks Reviewer to check the code
# 4. Coordinator compiles everything into a final report
```

---

## Common Patterns

### Pattern 1: Fallback

Try a capable but expensive model, fall back to cheaper one:

```elixir
defmodule SmartAgent do
  use Jido.Agent,
    name: "smart",
    strategy: {
      Jido.AI.Strategies.ReAct,
      model: "anthropic:claude-sonnet-4-20250514",
      max_iterations: 10
    }

  @impl true
  def chat(agent, message, opts \\ []) do
    # First try with Sonnet
    case super(agent, message, opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, :rate_limited} ->
        # Fall back to Haiku
        IO.puts("Rate limited, switching to Haiku")
        # Switch model and retry...
    end
  end
end
```

### Pattern 2: Caching

Cache common queries:

```elixir
defmodule CachedAgent do
  use Jido.Agent,
    name: "cached"

  def get_cached_response(agent, query) do
    case Cache.get(query) do
      {:ok, cached} ->
        {:ok, cached}

      :miss ->
        {:ok, response} = chat(agent, query)
        Cache.put(query, response, ttl: :timer.hours(24))
        {:ok, response}
    end
  end
end
```

### Pattern 3: Streaming

Handle long responses with streaming:

```elixir
defmodule StreamingAgent do
  use Jido.Agent,
    name: "streaming"

  def chat_stream(agent, message, callback) do
    # Start streaming
    {:ok, stream} = call(agent, %{"message" => message})

    # Process each chunk
    stream
    |> Stream.each(fn chunk ->
      callback.(chunk.delta)
    end)
    |> Stream.run()
  end
end

# Usage
StreamingAgent.chat_stream(agent, "Tell me a long story", fn chunk ->
  IO.write(chunk)  # Real-time output
end)
```

---

## Next Steps

- [Getting Started](./01_getting_started.md) - New to Jido.AI?
- [Strategies Guide](./03_strategies.md) - Learn about strategies
- [Tools & Actions Guide](./04_tools_actions.md) - Build your own tools
