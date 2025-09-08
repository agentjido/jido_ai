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
