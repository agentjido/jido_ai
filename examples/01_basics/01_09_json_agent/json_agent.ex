defmodule JidoAI.Examples.JSONAgent.Add do
  @moduledoc "Adds two integers for the JSON Agent example."

  use Jido.Action,
    name: "json_example_add",
    description: "Add two integers",
    schema: Zoi.object(%{left: Zoi.integer(), right: Zoi.integer()})

  def run(%{left: left, right: right}, _context), do: {:ok, %{sum: left + right}}
end

defmodule JidoAI.Examples.JSONAgent.AddFlow do
  @moduledoc "Runs the addition Action through a Flow."

  use Jido.Flow,
    name: "json_example_add_flow",
    description: "Add two integers through a Flow",
    schema: Zoi.object(%{left: Zoi.integer(), right: Zoi.integer()})

  flow do
    step "add", action: JidoAI.Examples.JSONAgent.Add, params: input()
    output result("add")
  end
end

defmodule JidoAI.Examples.JSONAgent.Permit do
  @moduledoc "Permits one imported AI request."

  use Jido.Action,
    name: "json_example_permit",
    description: "Permit an AI request",
    schema: Zoi.object(%{input: Zoi.string()})

  def run(_params, _context), do: {:ok, %{allowed: true}}
end

defmodule JidoAI.Examples.JSONAgent.Ask do
  @moduledoc "Defines the imported request and reply contract."

  use Jido.SignalAction,
    name: "json_example_ask",
    description: "Ask the JSON AI Agent for one answer",
    vsn: 1,
    input: [
      type: "examples.json_ai.ask",
      default_source: "/examples/json-ai/client",
      schema: Zoi.object(%{question: Zoi.string()})
    ],
    output: [
      type: "examples.json_ai.answered",
      default_source: "/examples/json-ai",
      schema:
        Zoi.object(%{
          answer: Zoi.string(),
          confidence: Zoi.number() |> Zoi.min(0) |> Zoi.max(1)
        })
    ]

  @impl Jido.Action
  def run(%{question: question}, context),
    do: Jido.AI.respond(context, question, reply: __MODULE__)
end

defmodule JidoAI.Examples.JSONAgent.HandleAsk do
  @moduledoc "Reasons and emits one typed reply as a Flow."

  alias JidoAI.Examples.JSONAgent.Ask

  use Jido.Flow,
    id: "examples/flows/json-handle-ask",
    name: "json_example_handle_ask",
    description: "Handle one JSON AI Agent request",
    schema: Ask.schema(),
    extensions: [Jido.AI.Flow.Extension]

  flow do
    reason("answer",
      prompt: input(:question),
      reply: Ask
    )

    step "reply",
         answer <- result("answer", :output),
         inline: [
           description: "Emit one typed imported Agent reply",
           schema: Zoi.object(%{answer: Ask.output_schema()}),
           context: context
         ] do
      Jido.AI.Turn.complete_reply(context, Ask, answer)
    end

    output result("reply")
  end
end

defmodule JidoAI.Examples.JSONAgent.Agent do
  @moduledoc "An AI Agent that can be exported and imported as JSON."

  alias JidoAI.Examples.JSONAgent.{Add, AddFlow, Ask, HandleAsk, Permit}

  use Jido.AI.Agent,
    id: "examples/agents/json-ai",
    name: "json_ai_example"

  ai do
    model :fast
    instructions "Use a tool when arithmetic is required."

    tools do
      action Add, as: :add_numbers
      flow AddFlow
    end

    controls do
      timeout 30_000
      max_iterations 3
      max_model_calls 4
      max_tool_calls 5
      input Permit
    end
  end

  routes do
    signal_source "/examples/json-ai"

    route Ask,
      via: HandleAsk,
      as: :ask,
      emits: ["examples.json_ai.answered"]
  end
end

defmodule JidoAI.Examples.JSONAgent do
  @moduledoc "Exports and imports the complete JSON AI Agent definition."

  alias Jido.Authoring.Registry
  alias JidoAI.Examples.JSONAgent.{Add, AddFlow, Agent, HandleAsk, Permit}

  @doc "Returns the compiled definition used to create the JSON document."
  def definition, do: Agent.definition()

  @doc "Returns the trusted references allowed in the document."
  def registry do
    Registry.new!(%{
      {"examples/agents/json-ai", 1} => {:agent, Agent},
      {"examples/schemas/json-ai-state", 1} => {:schema, definition().schema},
      {"jido.ai", 1} => {:plugin, Jido.AI.Plugin},
      {"examples/actions/json-add", 1} => {:action, Add},
      {"examples/flows/json-add", 1} => {:flow, AddFlow},
      {"examples/actions/json-permit", 1} => {:action, Permit},
      {"examples/flows/json-handle-ask", 1} => {:flow, HandleAsk},
      {"examples/atoms/ask", 1} => {:atom, :ask}
    })
  end

  @doc "Exports the current Agent definition as JSON."
  def encode_json do
    Jido.Authoring.encode_json(definition(), registry: registry(), codec: Jido.Agent.Codec)
  end

  @doc "Reads the saved JSON definition."
  def fixture_json, do: File.read!(Path.join(__DIR__, "fixtures/agent.json"))

  @doc "Imports the saved JSON without starting an Agent or calling a model."
  def import do
    Jido.Authoring.decode_json(fixture_json(), registry: registry(), codec: Jido.Agent.Codec)
  end
end
