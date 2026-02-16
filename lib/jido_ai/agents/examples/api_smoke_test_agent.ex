defmodule Jido.AI.Examples.ApiSmokeTestAgent do
  @moduledoc """
  Agent for API endpoint testing and debugging (`Jido.AI.Agent`, ReAct strategy implied).

  Demonstrates iterative HTTP debugging:
  1. Makes initial request to target endpoint
  2. Analyzes response (status, headers, body)
  3. Suggests fixes and retries with adjustments
  4. Reports findings

  **Why ReAct?** API debugging is inherently a hypothesis → request → observe → adjust
  loop. ReAct enables iterative refinement until the issue is understood.

  ## Usage

      # Start the agent
      {:ok, pid} = Jido.start_agent(MyApp.Jido, Jido.AI.Examples.ApiSmokeTestAgent)

      # Test an endpoint
      :ok = Jido.AI.Examples.ApiSmokeTestAgent.ask(pid,
        "Test GET https://httpbin.org/get and tell me what headers it returns")

      # Check result
      agent = Jido.AgentServer.get(pid)
      agent.state.last_answer

  ## CLI Usage

      mix jido_ai --agent Jido.AI.Examples.ApiSmokeTestAgent \\
        "Test https://api.github.com/zen and report the response"

      mix jido_ai --agent Jido.AI.Examples.ApiSmokeTestAgent \\
        "Check if https://httpbin.org/status/500 is working correctly"

  ## Available Test Endpoints

  For testing, you can use httpbin.org:
  - https://httpbin.org/get - Returns GET request data
  - https://httpbin.org/post - Accepts POST requests
  - https://httpbin.org/status/:code - Returns specific status codes
  - https://httpbin.org/headers - Returns request headers
  - https://httpbin.org/delay/:seconds - Delayed response
  """
  use Jido.AI.Agent,
    # Define HTTP test tools using ReqTool
    name: "api_smoke_test_agent",
    description: "API endpoint tester and debugger using ReAct reasoning",
    tools: [
      __MODULE__.Tools.HttpGet,
      __MODULE__.Tools.HttpPost
    ],
    system_prompt: """
    You are an API testing and debugging assistant. Your job is to test HTTP
    endpoints and help diagnose issues.

    When testing APIs:
    1. Start with the simplest request (GET with no special headers)
    2. Analyze the response carefully:
       - Status code: 2xx success, 3xx redirect, 4xx client error, 5xx server error
       - Headers: Content-Type, authentication requirements, rate limits
       - Body: Valid JSON/HTML/text? Error messages?
    3. If the request fails, hypothesize why and try adjustments
    4. Report findings clearly

    Common debugging steps:
    - 401/403: Check if authentication is needed
    - 404: Verify the URL path
    - 500: Server error - report and note it's not a client issue
    - Timeout: Note the endpoint may be slow or down

    Always provide:
    - The status code received
    - Key headers (Content-Type, etc.)
    - A summary of the response body
    - Your assessment of whether the API is working correctly
    """,
    max_iterations: 10

  defmodule Tools do
    @moduledoc false

    defmodule HttpGet do
      @moduledoc "Make an HTTP GET request to a URL"
      use Jido.Action,
        name: "http_get",
        description: "Make an HTTP GET request to test an endpoint",
        schema: [
          url: [type: :string, required: true, doc: "The URL to request"],
          headers: [type: :map, default: %{}, doc: "Optional headers to include"]
        ]

      @impl true
      def run(%{url: url} = params, _context) do
        headers = Map.get(params, :headers, %{}) |> Map.to_list()

        case Req.get(url, headers: headers) do
          {:ok, response} ->
            {:ok,
             %{
               status: response.status,
               headers: Map.new(response.headers),
               body: truncate_body(response.body),
               url: url
             }}

          {:error, reason} ->
            {:error, "Request failed: #{inspect(reason)}"}
        end
      end

      defp truncate_body(body) when is_binary(body) and byte_size(body) > 1000 do
        String.slice(body, 0, 1000) <> "... (truncated)"
      end

      defp truncate_body(body) when is_binary(body), do: body
      defp truncate_body(body), do: inspect(body, limit: 50)
    end

    defmodule HttpPost do
      @moduledoc "Make an HTTP POST request to a URL"
      use Jido.Action,
        name: "http_post",
        description: "Make an HTTP POST request with JSON body",
        schema: [
          url: [type: :string, required: true, doc: "The URL to request"],
          body: [type: :map, default: %{}, doc: "JSON body to send"],
          headers: [type: :map, default: %{}, doc: "Optional headers to include"]
        ]

      @impl true
      def run(%{url: url} = params, _context) do
        body = Map.get(params, :body, %{})
        headers = Map.get(params, :headers, %{}) |> Map.to_list()

        case Req.post(url, json: body, headers: headers) do
          {:ok, response} ->
            {:ok,
             %{
               status: response.status,
               headers: Map.new(response.headers),
               body: truncate_body(response.body),
               url: url
             }}

          {:error, reason} ->
            {:error, "Request failed: #{inspect(reason)}"}
        end
      end

      defp truncate_body(body) when is_binary(body) and byte_size(body) > 1000 do
        String.slice(body, 0, 1000) <> "... (truncated)"
      end

      defp truncate_body(body) when is_binary(body), do: body
      defp truncate_body(body), do: inspect(body, limit: 50)
    end
  end
end
