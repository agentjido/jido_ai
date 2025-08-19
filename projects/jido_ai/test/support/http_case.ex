defmodule Jido.AI.TestSupport.HTTPCase do
  @moduledoc """
  ExUnit case template for HTTP-based tests.

  Auto-configures Req.Test and provides convenient macros for HTTP mocking.
  Automatically calls `Req.Test.verify!/1` on test exit.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Jido.AI.TestSupport.HTTPCase

      alias Jido.AI.TestSupport.Fixtures
    end
  end

  setup _tags do
    # Set up HTTP client with unique test plug name based on test module
    test_name = :"http_case_#{:rand.uniform(1_000_000)}"

    Application.put_env(:jido_ai, :http_client, Req)
    Application.put_env(:jido_ai, :http_options, plug: {Req.Test, test_name})

    # Auto-verify all stubs are called on test exit
    on_exit(fn ->
      try do
        Req.Test.verify!(test_name)
      rescue
        _ -> :ok
      end
    end)

    {:ok, test_name: test_name}
  end

  @doc """
  Stubs a successful HTTP response with the given body.

  Uses the test_name from the test context automatically.
  """
  def stub_success(body, test_name \\ :http_case) do
    Req.Test.stub(test_name, &Req.Test.json(&1, body))
  end

  @doc """
  Stubs an HTTP error response with status code and error body.

  Uses the test_name from the test context automatically.
  """
  def stub_error(status, body, test_name \\ :http_case) do
    Req.Test.stub(test_name, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(status, Jason.encode!(body))
    end)
  end

  @doc """
  Stubs a transport error (connection timeout, DNS failure, etc.).

  Uses the test_name from the test context automatically.
  """
  def stub_transport_error(error_reason, test_name \\ :http_case) do
    Req.Test.stub(test_name, &Req.Test.transport_error(&1, error_reason))
  end

  @doc """
  Stubs a Server-Sent Events streaming response with the given event chunks.

  Uses the test_name from the test context automatically.
  """
  def stub_sse_stream(events, test_name \\ :http_case) do
    stub_sse(events, test_name)
  end

  def stub_sse(events, test_name \\ :http_case) do
    Req.Test.stub(test_name, fn conn ->
      conn =
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.put_resp_header("cache-control", "no-cache")
        |> Plug.Conn.send_chunked(200)

      conn =
        Enum.reduce(events, conn, fn event, acc ->
          chunk_data = Jason.encode!(event)
          {:ok, acc} = Plug.Conn.chunk(acc, "data: #{chunk_data}\n\n")
          acc
        end)

      {:ok, conn} = Plug.Conn.chunk(conn, "data: [DONE]\n\n")
      conn
    end)
  end

  @doc """
  Convenience macro that stubs a successful HTTP response with the given body.

  ## Examples

      with_success(%{choices: [%{message: %{content: "Hello"}}]}) do
        # Test code that expects successful response
      end
  """
  defmacro with_success(body, do: block) do
    quote do
      test_name = var!(test_name)
      stub_success(unquote(body), test_name)
      unquote(block)
    end
  end

  @doc """
  Convenience macro that stubs an HTTP error response with status code and error body.

  ## Examples

      with_error(429, %{error: %{message: "Rate limited"}}) do
        # Test code that expects rate limit error
      end
  """
  defmacro with_error(status, body, do: block) do
    quote do
      test_name = var!(test_name)
      stub_error(unquote(status), unquote(body), test_name)
      unquote(block)
    end
  end

  @doc """
  Convenience macro that stubs a transport error.

  ## Examples

      with_transport_error(:timeout) do
        # Test code that expects transport timeout
      end
  """
  defmacro with_transport_error(error_reason, do: block) do
    quote do
      test_name = var!(test_name)
      stub_transport_error(unquote(error_reason), test_name)
      unquote(block)
    end
  end

  @doc """
  Convenience macro that stubs a Server-Sent Events streaming response.

  ## Examples

      with_sse([
        %{choices: [%{delta: %{content: "Hello"}}]},
        %{choices: [%{delta: %{content: " world"}}]}
      ]) do
        # Test code that expects streaming response
      end
  """
  defmacro with_sse(events, do: block) do
    quote do
      test_name = var!(test_name)
      stub_sse(unquote(events), test_name)
      unquote(block)
    end
  end
end
