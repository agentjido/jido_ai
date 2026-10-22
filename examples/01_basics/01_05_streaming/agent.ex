defmodule JidoAI.Examples.Streaming.Agent do
  @moduledoc "A response that exposes ReqLLM text chunks."

  use Jido.AI.Agent, name: "streaming_example"

  ai do
    model :fast
    instructions "Reply in short chunks."
  end
end
