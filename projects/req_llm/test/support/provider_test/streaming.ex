defmodule ReqLLM.ProviderTest.Streaming do
  @moduledoc """
  Streaming text generation tests.

  Tests stream-based generation features:
  - Basic streaming with text chunks
  - Stream interruption and error handling
  - Chunk validation and parsing
  - Stream completion and termination
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

      # TODO: Implement streaming test macros
      # Will include tests for stream_text/3, chunk handling, etc.

      # Example tests that could be implemented:
      #
      # test "basic streaming completion" do
      #   result =
      #     use_fixture(unquote(provider), "basic_streaming", fn ->
      #       unquote(model)
      #       |> ReqLLM.stream_text("Hello world!", max_tokens: 20)
      #       |> Enum.to_list()
      #     end)
      #
      #   assert is_list(result)
      #   assert length(result) > 0
      # end
    end
  end
end
