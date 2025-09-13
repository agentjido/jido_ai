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

  ## Available Test Modules

  Each test module is now in its own file for better organization and macro expansion:

  - `ReqLLM.ProviderTest.Core` - Basic text generation functionality (prompts, parameters, responses)
  - `ReqLLM.ProviderTest.Streaming` - Stream-based text generation
  - `ReqLLM.ProviderTest.ToolCalling` - Tool/function calling capabilities

  ## Expanding the Test Suite

  To add new test macros:

  1. Create a new module file in `test/support/provider_test/`
  2. Define your macro with `defmacro __using__(opts)`
  3. Use the standard pattern: extract `provider` and `model` from opts
  4. Include appropriate moduletags and fixtures

  See existing modules for examples and patterns.
  """
end
