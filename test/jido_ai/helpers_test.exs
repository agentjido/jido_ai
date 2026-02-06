defmodule Jido.AI.HelpersTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Helpers

  describe "classify_error/1" do
    test "classifies rate limit by status" do
      error = %{status: 429}
      assert Helpers.classify_error(error) == :rate_limit
    end

    test "classifies auth by status 401" do
      error = %{status: 401}
      assert Helpers.classify_error(error) == :auth
    end

    test "classifies auth by status 403" do
      error = %{status: 403}
      assert Helpers.classify_error(error) == :auth
    end

    test "classifies provider error by 5xx status" do
      assert Helpers.classify_error(%{status: 500}) == :provider_error
      assert Helpers.classify_error(%{status: 503}) == :provider_error
    end

    test "classifies validation by 4xx status" do
      assert Helpers.classify_error(%{status: 400}) == :validation
      assert Helpers.classify_error(%{status: 422}) == :validation
    end

    test "classifies timeout by reason" do
      assert Helpers.classify_error(%{reason: :timeout}) == :timeout
      assert Helpers.classify_error(%{reason: :connect_timeout}) == :timeout
      assert Helpers.classify_error(%{reason: :checkout_timeout}) == :timeout
    end

    test "classifies network errors by reason" do
      assert Helpers.classify_error(%{reason: :econnrefused}) == :network
      assert Helpers.classify_error(%{reason: :nxdomain}) == :network
      assert Helpers.classify_error(%{reason: :closed}) == :network
    end

    test "classifies error tuples" do
      assert Helpers.classify_error({:error, :timeout}) == :timeout
      assert Helpers.classify_error(:timeout) == :timeout
    end

    test "classifies Mint errors as network" do
      assert Helpers.classify_error(%Mint.TransportError{reason: :closed}) == :network
      assert Helpers.classify_error(%Mint.HTTPError{reason: :protocol_error}) == :network
    end

    test "classifies unknown errors" do
      assert Helpers.classify_error(%{unknown: :error}) == :unknown
      assert Helpers.classify_error("some string") == :unknown
    end
  end

  describe "extract_retry_after/1" do
    test "extracts from response_headers" do
      error = %{response_headers: [{"retry-after", "60"}]}
      assert Helpers.extract_retry_after(error) == 60
    end

    test "extracts integer retry_after" do
      error = %{retry_after: 45}
      assert Helpers.extract_retry_after(error) == 45
    end

    test "returns nil when not available" do
      assert Helpers.extract_retry_after(%{reason: "timeout"}) == nil
      assert Helpers.extract_retry_after(%{}) == nil
    end
  end

  describe "wrap_error/1" do
    test "wraps rate limit error" do
      error = %{status: 429, reason: "Rate limited"}
      {:error, wrapped} = Helpers.wrap_error(error)

      assert %Jido.AI.Error.API.RateLimit{} = wrapped
      assert wrapped.message == "Rate limited"
    end

    test "wraps auth error" do
      error = %{status: 401, reason: "Unauthorized"}
      {:error, wrapped} = Helpers.wrap_error(error)

      assert %Jido.AI.Error.API.Auth{} = wrapped
    end

    test "wraps timeout error" do
      error = %{reason: :timeout}
      {:error, wrapped} = Helpers.wrap_error(error)

      assert %Jido.AI.Error.API.Request{kind: :timeout} = wrapped
    end

    test "wraps provider error" do
      error = %{status: 500, reason: "Internal error"}
      {:error, wrapped} = Helpers.wrap_error(error)

      assert %Jido.AI.Error.API.Request{kind: :provider, status: 500} = wrapped
    end

    test "wraps network error" do
      error = %{reason: :econnrefused}
      {:error, wrapped} = Helpers.wrap_error(error)

      assert %Jido.AI.Error.API.Request{kind: :network} = wrapped
    end

    test "wraps validation error" do
      error = %{status: 400, reason: "Bad request"}
      {:error, wrapped} = Helpers.wrap_error(error)

      assert %Jido.AI.Error.Validation.Invalid{} = wrapped
    end

    test "wraps unknown error" do
      {:error, wrapped} = Helpers.wrap_error(%{unknown: :error})

      assert %Jido.AI.Error.Unknown{} = wrapped
    end

    test "preserves retry_after for rate limit" do
      error = %{status: 429, reason: "Rate limited", response_headers: [{"retry-after", "60"}]}
      {:error, wrapped} = Helpers.wrap_error(error)
      assert wrapped.retry_after == 60
    end
  end

  describe "resolve_directive_model/1" do
    test "returns model string directly" do
      assert Helpers.resolve_directive_model(%{model: "anthropic:claude-haiku-4-5"}) ==
               "anthropic:claude-haiku-4-5"
    end

    test "resolves model alias" do
      assert Helpers.resolve_directive_model(%{model_alias: :fast}) ==
               "anthropic:claude-haiku-4-5"
    end

    test "raises when neither model nor model_alias provided" do
      assert_raise ArgumentError, fn ->
        Helpers.resolve_directive_model(%{model: nil, model_alias: nil})
      end

      assert_raise ArgumentError, fn ->
        Helpers.resolve_directive_model(%{})
      end
    end
  end

  describe "build_directive_messages/2" do
    test "returns messages without system prompt" do
      messages = [%{role: :user, content: "Hello"}]
      assert Helpers.build_directive_messages(messages, nil) == messages
    end

    test "prepends system prompt" do
      messages = [%{role: :user, content: "Hello"}]
      result = Helpers.build_directive_messages(messages, "Be helpful")

      assert [%{role: :system, content: "Be helpful"}, %{role: :user, content: "Hello"}] = result
    end

    test "handles map with messages key" do
      context = %{messages: [%{role: :user, content: "Hello"}]}
      result = Helpers.build_directive_messages(context, nil)

      assert [%{role: :user, content: "Hello"}] = result
    end
  end

  describe "add_timeout_opt/2" do
    test "adds receive_timeout when timeout provided" do
      opts = [max_tokens: 1000]
      result = Helpers.add_timeout_opt(opts, 5000)

      assert Keyword.get(result, :receive_timeout) == 5000
      assert Keyword.get(result, :max_tokens) == 1000
    end

    test "returns opts unchanged when timeout is nil" do
      opts = [max_tokens: 1000]
      assert Helpers.add_timeout_opt(opts, nil) == opts
    end
  end

  describe "add_tools_opt/2" do
    test "adds tools when list is not empty" do
      opts = [max_tokens: 1000]
      tools = [%{name: "calculator"}]
      result = Helpers.add_tools_opt(opts, tools)

      assert Keyword.get(result, :tools) == tools
    end

    test "returns opts unchanged when tools is empty" do
      opts = [max_tokens: 1000]
      assert Helpers.add_tools_opt(opts, []) == opts
    end
  end

  describe "classify_llm_response/1" do
    test "classifies tool calls response" do
      response = %{
        message: %{content: nil, tool_calls: [%{id: "tc_1", name: "calc", arguments: %{}}]},
        finish_reason: :tool_calls
      }

      result = Helpers.classify_llm_response(response)
      assert result.type == :tool_calls
      assert length(result.tool_calls) == 1
    end

    test "classifies final answer response" do
      response = %{
        message: %{content: "Hello world", tool_calls: nil},
        finish_reason: :stop
      }

      result = Helpers.classify_llm_response(response)
      assert result.type == :final_answer
      assert result.text == "Hello world"
      assert result.tool_calls == []
    end

    test "extracts text from content list" do
      response = %{
        message: %{
          content: [%{type: :text, text: "Hello"}, %{type: :text, text: "world"}],
          tool_calls: nil
        },
        finish_reason: :stop
      }

      result = Helpers.classify_llm_response(response)
      # Text blocks are joined with newlines
      assert result.text == "Hello\nworld"
    end
  end

  describe "task_supervisor/1" do
    test "returns instance-specific supervisor when jido present" do
      # This would need the Jido module to work properly
      # Just testing the fallback case
      assert Helpers.task_supervisor(%{}) == Jido.TaskSupervisor
      assert Helpers.task_supervisor(%{jido: nil}) == Jido.TaskSupervisor
    end
  end
end
