defmodule Jido.AI.HelpersTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Helpers
  alias ReqLLM.Context
  alias ReqLLM.Message.ContentPart

  describe "build_messages/2" do
    test "builds context from string prompt" do
      {:ok, context} = Helpers.build_messages("Hello")

      assert %Context{} = context
      assert length(context.messages) == 1
      [msg] = context.messages
      assert msg.role == :user
    end

    test "builds context with system prompt" do
      {:ok, context} = Helpers.build_messages("Hello", system_prompt: "You are helpful")

      assert length(context.messages) == 2
      [system_msg, user_msg] = context.messages
      assert system_msg.role == :system
      assert user_msg.role == :user
    end

    test "returns error for invalid input" do
      {:error, _reason} = Helpers.build_messages(%{invalid: :data})
    end
  end

  describe "build_messages!/2" do
    test "returns context on success" do
      context = Helpers.build_messages!("Hello")
      assert %Context{} = context
    end

    test "raises on invalid input" do
      assert_raise ArgumentError, fn ->
        Helpers.build_messages!(%{invalid: :data})
      end
    end
  end

  describe "add_system_message/2" do
    test "prepends system message to context" do
      context = Context.new([Context.user("Hello")])
      updated = Helpers.add_system_message(context, "You are helpful")

      assert length(updated.messages) == 2
      [system_msg, _user_msg] = updated.messages
      assert system_msg.role == :system
    end

    test "does not add system message if one exists" do
      context =
        Context.new([
          Context.system("Existing system"),
          Context.user("Hello")
        ])

      updated = Helpers.add_system_message(context, "New system")

      assert length(updated.messages) == 2
      [system_msg, _user_msg] = updated.messages
      # Original system message preserved
      assert hd(system_msg.content).text == "Existing system"
    end
  end

  describe "add_tool_result/4" do
    test "appends tool result message" do
      context = Context.new([Context.user("Hello")])
      updated = Helpers.add_tool_result(context, "call_123", "calculator", %{result: 42})

      assert length(updated.messages) == 2
      [_user_msg, tool_msg] = updated.messages
      assert tool_msg.role == :tool
      assert tool_msg.tool_call_id == "call_123"
      assert tool_msg.name == "calculator"
    end

    test "JSON encodes map results" do
      context = Context.new([])
      updated = Helpers.add_tool_result(context, "call_1", "test", %{value: "data"})

      [tool_msg] = updated.messages
      content_text = hd(tool_msg.content).text
      assert content_text =~ "value"
      assert content_text =~ "data"
    end
  end

  describe "extract_text/1" do
    test "extracts string content" do
      response = %{message: %{content: "Hello world"}}
      assert Helpers.extract_text(response) == "Hello world"
    end

    test "extracts text from ContentPart list" do
      response = %{
        message: %{
          content: [
            %ContentPart{type: :text, text: "First "},
            %ContentPart{type: :text, text: "Second"}
          ]
        }
      }

      assert Helpers.extract_text(response) == "First Second"
    end

    test "extracts text from plain maps" do
      response = %{
        message: %{
          content: [
            %{type: :text, text: "Hello"},
            %{type: :image, url: "..."},
            %{type: :text, text: " World"}
          ]
        }
      }

      assert Helpers.extract_text(response) == "Hello World"
    end

    test "returns empty string for missing content" do
      assert Helpers.extract_text(%{}) == ""
      assert Helpers.extract_text(%{message: %{}}) == ""
    end
  end

  describe "extract_tool_calls/1" do
    test "extracts tool calls from response" do
      response = %{
        message: %{
          tool_calls: [
            %{id: "tc_1", name: "calculator", arguments: %{a: 1, b: 2}}
          ]
        }
      }

      [tool_call] = Helpers.extract_tool_calls(response)
      assert tool_call.id == "tc_1"
      assert tool_call.name == "calculator"
      assert tool_call.arguments == %{a: 1, b: 2}
    end

    test "extracts from ReqLLM.ToolCall structs" do
      tool_call = ReqLLM.ToolCall.new("tc_2", "search", ~s({"query":"test"}))

      response = %{
        message: %{
          tool_calls: [tool_call]
        }
      }

      [extracted] = Helpers.extract_tool_calls(response)
      assert extracted.name == "search"
      assert extracted.arguments == %{"query" => "test"}
    end

    test "returns empty list for no tool calls" do
      assert Helpers.extract_tool_calls(%{message: %{content: "Hello"}}) == []
      assert Helpers.extract_tool_calls(%{}) == []
    end
  end

  describe "has_tool_calls?/1" do
    test "returns true when tool calls present" do
      response = %{message: %{tool_calls: [%{id: "tc_1"}]}}
      assert Helpers.has_tool_calls?(response) == true
    end

    test "returns false for empty tool calls" do
      assert Helpers.has_tool_calls?(%{message: %{tool_calls: []}}) == false
    end

    test "returns false for no tool calls" do
      assert Helpers.has_tool_calls?(%{message: %{content: "Hello"}}) == false
      assert Helpers.has_tool_calls?(%{}) == false
    end
  end

  describe "classify_response/1" do
    test "classifies tool calls response" do
      response = %{message: %{tool_calls: [%{id: "tc_1"}]}}
      assert Helpers.classify_response(response) == :tool_calls
    end

    test "classifies final answer response" do
      response = %{message: %{content: "Hello"}}
      assert Helpers.classify_response(response) == :final_answer
    end

    test "classifies error response" do
      assert Helpers.classify_response({:error, %{reason: "timeout"}}) == :error
    end

    test "classifies invalid as error" do
      assert Helpers.classify_response(%{}) == :error
      assert Helpers.classify_response(nil) == :error
    end
  end

  describe "classify_error/1" do
    test "classifies rate limit by status" do
      error = %ReqLLM.Error.API.Request{status: 429, reason: "Too many requests"}
      assert Helpers.classify_error(error) == :rate_limit
    end

    test "classifies auth by status 401" do
      error = %ReqLLM.Error.API.Request{status: 401, reason: "Unauthorized"}
      assert Helpers.classify_error(error) == :auth
    end

    test "classifies auth by status 403" do
      error = %ReqLLM.Error.API.Request{status: 403, reason: "Forbidden"}
      assert Helpers.classify_error(error) == :auth
    end

    test "classifies provider error by 5xx status" do
      error = %ReqLLM.Error.API.Request{status: 500, reason: "Internal Server Error"}
      assert Helpers.classify_error(error) == :provider_error

      error = %ReqLLM.Error.API.Request{status: 503, reason: "Service Unavailable"}
      assert Helpers.classify_error(error) == :provider_error
    end

    test "classifies timeout by reason string" do
      error = %ReqLLM.Error.API.Request{reason: "Request timeout after 30s"}
      assert Helpers.classify_error(error) == :timeout
    end

    test "classifies network errors" do
      error = %ReqLLM.Error.API.Request{reason: "econnrefused"}
      assert Helpers.classify_error(error) == :network

      error = %ReqLLM.Error.API.Request{reason: "nxdomain"}
      assert Helpers.classify_error(error) == :network
    end

    test "classifies validation errors" do
      error = ReqLLM.Error.validation_error(:invalid, "Bad input", [])
      assert Helpers.classify_error(error) == :validation
    end

    test "classifies unknown errors" do
      assert Helpers.classify_error(%{unknown: :error}) == :unknown
      assert Helpers.classify_error("some string") == :unknown
    end

    test "classifies error tuples" do
      assert Helpers.classify_error({:error, :timeout}) == :timeout
      assert Helpers.classify_error({:error, :econnrefused}) == :network
    end
  end

  describe "extract_retry_after/1" do
    test "extracts from nested error response body" do
      error = %{response_body: %{"error" => %{"retry_after" => 60}}}
      assert Helpers.extract_retry_after(error) == 60
    end

    test "extracts string retry_after" do
      error = %{response_body: %{"error" => %{"retry_after" => "30"}}}
      assert Helpers.extract_retry_after(error) == 30
    end

    test "extracts from top-level response body" do
      error = %{response_body: %{"retry_after" => 45}}
      assert Helpers.extract_retry_after(error) == 45
    end

    test "extracts from reason string" do
      error = %{reason: "Rate limit exceeded. Retry-After: 120"}
      assert Helpers.extract_retry_after(error) == 120
    end

    test "returns nil when not available" do
      assert Helpers.extract_retry_after(%{reason: "timeout"}) == nil
      assert Helpers.extract_retry_after(%{}) == nil
    end
  end

  describe "wrap_error/1" do
    test "wraps rate limit error" do
      error = %ReqLLM.Error.API.Request{status: 429, reason: "Rate limited"}
      {:error, wrapped} = Helpers.wrap_error(error)

      assert %Jido.AI.Error.API.RateLimit{} = wrapped
      assert wrapped.message == "Rate limited"
    end

    test "wraps auth error" do
      error = %ReqLLM.Error.API.Request{status: 401, reason: "Unauthorized"}
      {:error, wrapped} = Helpers.wrap_error(error)

      assert %Jido.AI.Error.API.Auth{} = wrapped
    end

    test "wraps timeout error" do
      error = %ReqLLM.Error.API.Request{reason: "Request timeout"}
      {:error, wrapped} = Helpers.wrap_error(error)

      assert %Jido.AI.Error.API.Timeout{} = wrapped
    end

    test "wraps provider error" do
      error = %ReqLLM.Error.API.Request{status: 500, reason: "Internal error"}
      {:error, wrapped} = Helpers.wrap_error(error)

      assert %Jido.AI.Error.API.Provider{} = wrapped
    end

    test "wraps network error" do
      error = %ReqLLM.Error.API.Request{reason: "econnrefused"}
      {:error, wrapped} = Helpers.wrap_error(error)

      assert %Jido.AI.Error.API.Network{} = wrapped
    end

    test "wraps validation error" do
      error = ReqLLM.Error.validation_error(:invalid_param, "Bad param", [])
      {:error, wrapped} = Helpers.wrap_error(error)

      assert %Jido.AI.Error.Validation.Invalid{} = wrapped
    end

    test "wraps unknown error" do
      {:error, wrapped} = Helpers.wrap_error(%{unknown: :error})

      assert %Jido.AI.Error.Unknown{} = wrapped
    end

    test "preserves retry_after for rate limit" do
      error = %ReqLLM.Error.API.Request{
        status: 429,
        reason: "Rate limited",
        response_body: %{"retry_after" => 60}
      }

      {:error, wrapped} = Helpers.wrap_error(error)
      assert wrapped.retry_after == 60
    end
  end
end
