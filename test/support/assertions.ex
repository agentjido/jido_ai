defmodule Jido.AI.TestSupport.Assertions do
  @moduledoc """
  Custom assertions for testing AI provider implementations.
  """

  import ExUnit.Assertions

  alias Jido.AI.Model

  @doc """
  Extracts value from `{:ok, value}` tuple or fails the test.

  ## Examples

      result = some_function()
      value = assert_ok(result)  # Fails if result is not {:ok, _}
  """
  defmacro assert_ok(result) do
    quote do
      case unquote(result) do
        {:ok, value} -> value
        other -> flunk("Expected {:ok, _}, got: #{inspect(other)}")
      end
    end
  end

  @doc """
  Matches `{:error, %ErrorModule{}}` pattern or fails the test.

  ## Examples

      result = some_function()
      assert_error(result, Jido.AI.Error.APIError)
      assert_error(result, %Jido.AI.Error.APIError{status: 429})
  """
  defmacro assert_error(result, expected_error) when is_atom(expected_error) do
    quote do
      case unquote(result) do
        {:error, %{__struct__: error_module} = error} ->
          assert error_module == unquote(expected_error),
                 "Expected error module #{inspect(unquote(expected_error))}, got #{inspect(error_module)}"

          error

        {:error, other} ->
          flunk("Expected {:error, %#{inspect(unquote(expected_error))}{}}, got {:error, #{inspect(other)}}")

        other ->
          flunk("Expected {:error, %#{inspect(unquote(expected_error))}{}}, got: #{inspect(other)}")
      end
    end
  end

  defmacro assert_error(result, expected_pattern) do
    quote do
      case unquote(result) do
        {:error, error} = result ->
          assert match?(unquote(expected_pattern), error),
                 "Error #{inspect(error)} does not match pattern #{inspect(unquote(expected_pattern))}"

          error

        other ->
          flunk("Expected {:error, _} matching #{inspect(unquote(expected_pattern))}, got: #{inspect(other)}")
      end
    end
  end

  @doc """
  Asserts that an HTTP request was made with the expected structure.

  The assertion function receives the request and body, allowing verification
  of headers, URL, method, and request body structure.
  """
  defmacro assert_request(assertion_fn) do
    quote do
      assert_receive {:req_test_stub, _conn, request}
      unquote(assertion_fn).(request.body, request)
    end
  end

  @doc """
  Asserts that a stream contains the expected chunks in order.
  """
  def assert_stream_chunks(stream, expected_chunks) when is_list(expected_chunks) do
    actual_chunks = Enum.to_list(stream)
    assert actual_chunks == expected_chunks
  end

  @doc """
  Asserts that a model struct has the required fields populated.
  """
  def assert_valid_model(%Model{} = model) do
    assert is_atom(model.provider)
    assert is_binary(model.model)
    assert model.provider != nil
    assert model.model != ""
  end

  @doc """
  Asserts that a chat completion request body has required OpenAI API fields.
  """
  def assert_chat_completion_body(body) when is_map(body) do
    # Handle both string and atom keys
    model_key = if Map.has_key?(body, "model"), do: "model", else: :model
    messages_key = if Map.has_key?(body, "messages"), do: "messages", else: :messages

    assert Map.has_key?(body, model_key)
    assert Map.has_key?(body, messages_key)
    assert is_list(body[messages_key])
    refute Enum.empty?(body[messages_key])

    # Check first message structure
    message = List.first(body[messages_key])
    role_key = if Map.has_key?(message, "role"), do: "role", else: :role
    content_key = if Map.has_key?(message, "content"), do: "content", else: :content

    assert Map.has_key?(message, role_key)
    assert Map.has_key?(message, content_key)
  end

  @doc """
  Asserts that API key is properly configured for a provider.
  """
  def assert_api_key_configured(provider_module) do
    provider_info = provider_module.provider_info()

    # Should have at least one env var configured
    assert is_list(provider_info.env)
    refute Enum.empty?(provider_info.env)
  end
end
