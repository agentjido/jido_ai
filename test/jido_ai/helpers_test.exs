defmodule Jido.AI.Directive.HelpersTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Directive.Helpers

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

  describe "add_req_http_options/2" do
    test "adds req_http_options when provided" do
      opts = [max_tokens: 1000]
      req_http_options = [plug: {Req.Test, []}]
      result = Helpers.add_req_http_options(opts, req_http_options)

      assert Keyword.get(result, :req_http_options) == req_http_options
      assert Keyword.get(result, :max_tokens) == 1000
    end

    test "returns opts unchanged when req_http_options is nil or empty" do
      opts = [max_tokens: 1000]
      assert Helpers.add_req_http_options(opts, nil) == opts
      assert Helpers.add_req_http_options(opts, []) == opts
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
end
