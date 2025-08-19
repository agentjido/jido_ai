defmodule Jido.AI.Provider.BaseStreamObjectTest do
  use Jido.AI.TestSupport.HTTPCase

  alias Jido.AI.Provider.{Base, OpenAI}
  alias Jido.AI.Test.Fixtures.ModelFixtures

  describe "stream_object functionality" do
    test "stream_object returns a stream like stream_text", %{test_name: test_name} do
      model = ModelFixtures.gpt4()
      schema = [name: [type: :string, required: true]]

      # Mock streaming response
      events = [
        %{"choices" => [%{"delta" => %{"content" => "{\"name\":"}}]},
        %{"choices" => [%{"delta" => %{"content" => "\"John\"}"}}]}
      ]

      with_sse(events) do
        result = Base.default_stream_object(OpenAI, model, "Generate a person", schema)

        # Should return a stream successfully
        assert {:ok, stream} = result
        assert is_function(stream)
      end
    end
  end
end
