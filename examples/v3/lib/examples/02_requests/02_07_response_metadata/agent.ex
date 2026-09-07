defmodule JidoAI.Examples.ResponseMetadata.Agent do
  @moduledoc "Keeps model response metadata separate from the public answer."
  use Jido.AI.Agent,
    name: "response_metadata_agent",
    model: :example,
    tools: [JidoAI.Examples.RequestScope.Echo],
    streaming: false
end

defmodule JidoAI.Examples.ResponseMetadata.StreamAgent do
  @moduledoc "Collects the same response metadata from the real stream decoder."
  use Jido.AI.Agent,
    name: "stream_response_metadata_agent",
    model: :example,
    tools: [JidoAI.Examples.RequestScope.Echo],
    streaming: true
end
