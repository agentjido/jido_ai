defmodule ReqLLM.TestHelpers do
  @moduledoc """
  Test helpers for fixture-based testing with ReqLLM providers.

  Provides utilities for zero-network testing using JSON fixtures and Req.Test.
  """

  @fixtures_path Path.join([__DIR__, "..", "fixtures"])

  @doc """
  Loads a fixture and runs test code with mocked HTTP responses.

  ## Examples

      with_fixture("anthropic/completion_success") do
        result = ReqLLM.generate_text("anthropic:claude-3-sonnet", [%{role: :user, content: "Hello"}])
        assert {:ok, response} = result
        assert response =~ "Hello! How can I help you today?"
      end
  """
  @spec with_fixture(String.t(), function()) :: any()
  def with_fixture(fixture_path, test_fn) do
    stub = fixture_stub(fixture_path)
    Req.Test.expect(ReqLLM.FixtureStub, stub)
    test_fn.()
  end

  @doc """
  Creates a Req.Test plug from a fixture file path.

  ## Examples

      stub = fixture_stub("anthropic/completion_success")
      Req.Test.expect(ReqLLM.FixtureStub, stub)
  """
  @spec fixture_stub(String.t()) :: function()
  def fixture_stub(fixture_path) do
    fixture_data = load_fixture(fixture_path)

    fn _conn ->
      case fixture_data do
        # Handle streaming fixtures (arrays of events)
        events when is_list(events) ->
          # Convert events to SSE format
          sse_body =
            events
            |> Enum.map(&"data: #{Jason.encode!(&1)}\n\n")
            |> Enum.join("")

          %Req.Response{
            status: 200,
            body: sse_body,
            headers: [{"content-type", "text/event-stream"}]
          }

        # Handle non-streaming fixtures (single response objects)
        response when is_map(response) ->
          %Req.Response{
            status: 200,
            body: response,
            headers: [{"content-type", "application/json"}]
          }
      end
    end
  end

  @doc """
  Collects all chunks from a stream for test assertions.

  ## Examples

      stream = ReqLLM.stream_text("anthropic:claude-3-sonnet", [%{role: :user, content: "Hello"}])
      chunks = collect_chunks(stream)
      assert length(chunks) == 2
      assert Enum.any?(chunks, &(&1.text == "Hello"))
  """
  @spec collect_chunks(Enumerable.t()) :: [ReqLLM.StreamChunk.t()]
  def collect_chunks(stream) do
    Enum.to_list(stream)
  end

  @doc """
  Records a live API response to a fixture file (for future implementation).

  Currently just loads existing fixtures, but could be extended to record real responses.
  """
  @spec record_fixture(String.t(), String.t(), String.t(), keyword()) :: :ok
  def record_fixture(_provider, _scenario, _prompt, _opts \\ []) do
    # TODO: Implement real API recording for fixture generation
    :ok
  end

  # Private functions

  @spec load_fixture(String.t()) :: map() | [map()]
  defp load_fixture(fixture_path) do
    file_path = Path.join(@fixtures_path, fixture_path <> ".json")

    case File.read(file_path) do
      {:ok, json} ->
        Jason.decode!(json)

      {:error, reason} ->
        raise "Fixture not found: #{file_path} (#{reason})"
    end
  end
end

defmodule ReqLLM.FixtureStub do
  @moduledoc """
  Generic fixture stub namespace for Req.Test integration.

  This module serves as a namespace for fixture-based plugs created by
  ReqLLM.TestHelpers.fixture_stub/1.
  """

  # This module acts as a namespace for Req.Test.stub/2 calls
  # The actual plug functions are created by fixture_stub/1
end

# Add the capability testing functions that were in the other test_helpers.ex
defmodule ReqLLM.TestHelpers.Capability do
  @moduledoc """
  Additional test helpers specifically for capability testing.
  """

  import ExUnit.Assertions

  @doc """
  Creates a minimal fake model for testing.

  Returns a `ReqLLM.Model` struct with the fake provider and sensible defaults.
  Useful for capability discovery tests that don't require network calls.
  """
  @spec fake_model(keyword()) :: ReqLLM.Model.t()
  def fake_model(opts \\ []) do
    ReqLLM.Model.new(
      Keyword.get(opts, :provider, :fake),
      Keyword.get(opts, :model, "fake-model"),
      temperature: Keyword.get(opts, :temperature, 0.7),
      max_tokens: Keyword.get(opts, :max_tokens, 1000),
      max_retries: Keyword.get(opts, :max_retries, 3),
      capabilities:
        Keyword.get(opts, :capabilities, %{
          reasoning?: false,
          tool_call?: true,
          supports_temperature?: true
        }),
      modalities:
        Keyword.get(opts, :modalities, %{
          input: [:text],
          output: [:text]
        }),
      limit:
        Keyword.get(opts, :limit, %{
          context: 128_000,
          output: 4096
        }),
      cost:
        Keyword.get(opts, :cost, %{
          input: 0.001,
          output: 0.002
        })
    )
  end

  @doc """
  Sets up Req.Test with a default OpenAI-style chat completions responder.
  """
  @spec start_req_test(pid(), keyword()) :: :ok
  def start_req_test(pid, opts \\ []) do
    Req.Test.stub(ReqLLM, fn conn ->
      default_responder(conn, opts)
    end)

    Req.Test.allow(ReqLLM, pid, self())
    :ok
  end

  @doc """
  Default responder function for mock chat completions.
  """
  @spec default_responder(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def default_responder(conn, opts \\ [])

  def default_responder(%{request_path: path} = conn, opts)
      when path in ["/chat/completions", "/v1/chat/completions"] do
    content = Keyword.get(opts, :content, "Test response")
    finish_reason = Keyword.get(opts, :finish_reason, "stop")

    usage =
      Keyword.get(opts, :usage, %{
        prompt_tokens: 10,
        completion_tokens: 15,
        total_tokens: 25
      })

    response = %{
      id: "chatcmpl-test-#{:rand.uniform(1000)}",
      object: "chat.completion",
      created: System.system_time(:second),
      model: "fake-model",
      choices: [
        %{
          index: 0,
          message: %{
            role: "assistant",
            content: content
          },
          finish_reason: finish_reason
        }
      ],
      usage: usage
    }

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(200, Jason.encode!(response))
  end

  def default_responder(conn, _opts) do
    # Default 404 for unhandled endpoints
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(404, Jason.encode!(%{error: "Not found"}))
  end

  @doc """
  Asserts that a capability verification result has the expected status.
  """
  @spec assert_capability_status(ReqLLM.Capability.Result.t(), :passed | :failed) ::
          ReqLLM.Capability.Result.t()
  def assert_capability_status(%ReqLLM.Capability.Result{} = result, expected_status) do
    assert result.status == expected_status,
           "Expected capability status #{expected_status}, got #{result.status}"

    result
  end
end
