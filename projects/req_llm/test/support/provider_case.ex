defmodule ReqLLM.ProviderCase do
  @moduledoc """
  Minimal test case template that imports ReqLLM.TestHelpers for fixture-based testing.

  ## Usage

      defmodule ReqLLM.Providers.AnthropicTest do
        use ReqLLM.ProviderCase, async: true

        # Use fixture-based testing
        test "successful completion" do
          with_fixture("anthropic/completion_success") do
            # Test logic here
          end
        end
      end
  """

  use ExUnit.CaseTemplate

  using opts do
    quote do
      use ExUnit.Case, unquote(opts)
      import ReqLLM.TestHelpers
      alias ReqLLM.{Model, Error}
    end
  end
end
