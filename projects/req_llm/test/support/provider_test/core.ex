defmodule ReqLLM.ProviderTest.Core do
  @moduledoc """
  Core text generation functionality tests.

  Tests basic completion features that should work across all LLM providers:
  - Simple prompts with and without system messages
  - Parameter handling (temperature, max_tokens, etc.)  
  - Response parsing and validation
  - String vs Context input formats
  """

  defmacro __using__(opts) do
    provider = Keyword.fetch!(opts, :provider)
    model = Keyword.fetch!(opts, :model)

    quote bind_quoted: [provider: provider, model: model] do
      use ExUnit.Case, async: false

      import ReqLLM.Test.LiveFixture

      alias ReqLLM.Test.LiveFixture, as: ReqFixture

      @moduletag :coverage
      @moduletag provider

      test "basic completion without system prompt" do
        result =
          use_fixture(unquote(provider), "basic_completion", fn ->
            ctx = ReqLLM.Context.new([ReqLLM.Context.user("Hello!")])
            ReqLLM.generate_text(unquote(model), ctx, max_tokens: 5)
          end)

        {:ok, resp} = result
        text = ReqLLM.Response.text(resp)
        assert is_binary(text)
        assert text != ""
        assert resp.id != nil
      end

      test "completion with system prompt" do
        result =
          use_fixture(unquote(provider), "system_prompt_completion", fn ->
            ctx =
              ReqLLM.Context.new([
                ReqLLM.Context.system("You are terse. Reply with ONE word."),
                ReqLLM.Context.user("Greet me")
              ])

            ReqLLM.generate_text(unquote(model), ctx, max_tokens: 5)
          end)

        {:ok, resp} = result
        text = ReqLLM.Response.text(resp)
        assert is_binary(text)
        assert text != ""
        assert resp.id != nil
      end

      test "temperature parameter" do
        result =
          use_fixture(unquote(provider), "temperature_test", fn ->
            ReqLLM.generate_text(
              unquote(model),
              "Say exactly: TEMPERATURE_TEST",
              temperature: 0.0,
              max_tokens: 10
            )
          end)

        {:ok, resp} = result
        text = ReqLLM.Response.text(resp)
        assert is_binary(text)
        assert text != ""
        assert resp.id != nil
      end

      test "max_tokens parameter" do
        result =
          use_fixture(unquote(provider), "max_tokens_test", fn ->
            ReqLLM.generate_text(
              unquote(model),
              "Write a story",
              max_tokens: 5
            )
          end)

        {:ok, resp} = result
        text = ReqLLM.Response.text(resp)
        assert is_binary(text)
        assert text != ""
        assert resp.id != nil
        # Should be short due to max_tokens limit
        assert String.length(text) < 100
      end

      test "string prompt (legacy format)" do
        result =
          use_fixture(unquote(provider), "string_prompt", fn ->
            ReqLLM.generate_text(unquote(model), "Hello world!", max_tokens: 5)
          end)

        {:ok, resp} = result
        text = ReqLLM.Response.text(resp)
        assert is_binary(text)
        assert text != ""
        assert resp.id != nil
      end
    end
  end
end
