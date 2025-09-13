defmodule ReqLLM.ProviderTest do
  @moduledoc """
  Shared test macros for provider-specific testing.
  
  Provides a flexible macro system to eliminate duplication across provider test suites.
  Each macro contains common test scenarios that work across different LLM providers.
  
  ## Usage
  
      defmodule ReqLLM.Coverage.OpenAI.CoreTest do
        use ReqLLM.ProviderTest.Core,
            provider: :openai,
            model: "openai:gpt-4o-mini"
        
        # Provider-specific tests can be added here
      end
  
  ## Available Macros
  
  - `Core` - Basic text generation functionality (prompts, parameters, responses)
  - `Streaming` - Stream-based text generation (planned)  
  - `ToolCalling` - Tool/function calling capabilities (planned)
  """

  defmodule Core do
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
        
        alias ReqLLM.Test.LiveFixture, as: ReqFixture
        import ReqFixture
        
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

  defmodule Streaming do
    @moduledoc """
    Streaming text generation tests (planned).
    
    Tests stream-based generation features:
    - Basic streaming with text chunks
    - Stream interruption and error handling
    - Chunk validation and parsing
    """
    
    defmacro __using__(_opts) do
      quote do
        # TODO: Implement streaming test macros
        # Will include tests for stream_text/3, chunk handling, etc.
      end
    end
  end

  defmodule ToolCalling do
    @moduledoc """
    Tool/function calling tests (planned).
    
    Tests tool calling capabilities:
    - Tool definition and registration  
    - Parameter schema validation
    - Tool execution and result handling
    - Multi-tool scenarios
    """
    
    defmacro __using__(_opts) do
      quote do
        # TODO: Implement tool calling test macros
        # Will include tests for generate_object/4, tool schemas, etc.
      end
    end
  end
end
