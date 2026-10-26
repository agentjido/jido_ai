unless Code.ensure_loaded?(JidoAI.Examples.Tools.Add) do
  Code.require_file("../../support/arithmetic_tools.ex", __DIR__)
end

defmodule JidoAI.Examples.JSONSimpleAgent do
  @moduledoc false

  use Jido.AI.Agent,
    id: "jido.ai/agents/simple",
    vsn: 3,
    name: "jido_ai_simple_agent",
    description: "Answer one request with guardrails and multiple tools"

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      action JidoAI.Examples.Tools.Add
      action JidoAI.Examples.Tools.Multiply
    end
  end
end

defmodule JidoAI.Examples.JSONAgent do
  @moduledoc """
  Stores and loads the graph-first SimpleAgent with `Jido.Authoring`.

  The AI DSL lowers to a normal Agent route before execution. Its codec stores
  the core Agent fields and one trusted reference to the root reasoning Flow.
  """

  alias Jido.AI.Reasoning.ReAct
  alias Jido.Authoring.Registry
  alias JidoAI.Examples.JSONSimpleAgent, as: SimpleAgent

  @request_type "jido.ai.request"
  @fixture Path.join(__DIR__, "fixtures/agent.json")

  @doc "Returns the compiled graph-first Agent definition."
  def definition, do: SimpleAgent.definition()

  @doc "Returns the allowlist used to encode and decode the Agent document."
  def registry do
    Registry.new!(%{
      {"jido.ai/agents/simple", 3} => {:agent, SimpleAgent},
      {"jido.ai/reasoning/react", 1} => {:flow, ReAct},
      {"jido.ai/examples/tools/add", 1} => {:action, JidoAI.Examples.Tools.Add},
      {"jido.ai/examples/tools/multiply", 1} => {:action, JidoAI.Examples.Tools.Multiply},
      {"jido.ai/schemas/simple-agent-state", 1} => {:schema, definition().schema}
    })
  end

  @doc "Encodes the SimpleAgent definition with the AI Agent codec."
  def encode_json do
    Jido.Authoring.encode_json(definition(),
      registry: registry(),
      codec: Jido.AI.Agent.Codec
    )
  end

  @doc "Reads the stored SimpleAgent document."
  def fixture_json, do: File.read!(@fixture)

  @doc "Decodes and validates the stored SimpleAgent definition."
  def import do
    Jido.Authoring.decode_json(fixture_json(),
      registry: registry(),
      codec: Jido.AI.Agent.Codec
    )
  end

  @doc "Builds the standard AI request Signal for an imported definition."
  def request_signal!(definition, params) do
    Jido.Agent.input_signal!(definition, @request_type, params)
  end
end
