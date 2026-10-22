defmodule JidoAI.Examples.ModelHelpers.FastAgent do
  @moduledoc "An Agent that selects a configured model alias."

  use Jido.AI.Agent, name: "model_alias_example"

  ai do
    model :fast
  end
end

defmodule JidoAI.Examples.ModelHelpers.PinnedAgent do
  @moduledoc "An Agent that selects a direct ReqLLM model name."

  use Jido.AI.Agent, name: "direct_model_example"

  ai do
    model "anthropic:claude-haiku-4-5"
  end
end
