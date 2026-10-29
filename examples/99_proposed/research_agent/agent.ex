defmodule JidoAI.Examples.Proposed.ResearchAgent.SearchSources do
  @moduledoc "Returns deterministic local sources for one research query."

  use Jido.Action,
    name: "proposed_research_search_sources",
    description: "Find local sources for a research query",
    schema:
      Zoi.object(%{
        query: Zoi.string() |> Zoi.min(1),
        limit: Zoi.integer() |> Zoi.min(1) |> Zoi.max(5) |> Zoi.default(3)
      }),
    output_schema: Zoi.object(%{sources: Zoi.list(Zoi.string())})

  @impl Jido.Action
  def run(%{query: query, limit: limit}, _context) do
    slug =
      query
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    sources = for index <- 1..limit, do: "local://research/#{slug}/#{index}"
    {:ok, %{sources: sources}}
  end
end

defmodule JidoAI.Examples.Proposed.ResearchAgent.CompileBrief do
  @moduledoc "Builds one research brief from source identifiers."

  use Jido.Action,
    name: "proposed_research_compile_brief",
    description: "Compile source identifiers into a research brief",
    schema:
      Zoi.object(%{
        query: Zoi.string() |> Zoi.min(1),
        sources: Zoi.list(Zoi.string())
      }),
    output_schema:
      Zoi.object(%{
        brief: Zoi.string(),
        sources: Zoi.list(Zoi.string())
      })

  @impl Jido.Action
  def run(%{query: query, sources: sources}, _context) do
    source_list = Enum.map_join(sources, ", ", & &1)
    {:ok, %{brief: "Research for #{query}: #{source_list}", sources: sources}}
  end
end

defmodule JidoAI.Examples.Proposed.ResearchAgent.ResearchFlow do
  @moduledoc "Runs two core Jido Actions as one reusable research Flow."

  alias JidoAI.Examples.Proposed.ResearchAgent.{CompileBrief, SearchSources}

  use Jido.Flow,
    name: "proposed_research_flow",
    description: "Search sources and compile a research brief",
    schema:
      Zoi.object(%{
        query: Zoi.string() |> Zoi.min(1),
        limit: Zoi.integer() |> Zoi.min(1) |> Zoi.max(5) |> Zoi.default(3)
      }),
    output_schema:
      Zoi.object(%{
        brief: Zoi.string(),
        sources: Zoi.list(Zoi.string())
      })

  flow do
    step "search", action: SearchSources, params: input()

    step "compile",
      action: CompileBrief,
      params: %{
        query: input(:query),
        sources: result("search", :sources)
      }

    output result("compile")
  end
end

defmodule JidoAI.Examples.Proposed.ResearchAgent.ValidateRequest do
  @moduledoc "Checks the caller role and research query."

  use Jido.Action,
    name: "proposed_research_validate_request",
    description: "Require a research member and a useful query",
    schema: Zoi.object(%{input: Zoi.string()})

  @impl Jido.Action
  def run(%{input: query}, %{role: :researcher}) do
    if String.length(String.trim(query)) >= 8,
      do: {:ok, %{accepted: true}},
      else: {:error, :query_too_short}
  end

  def run(_params, _context), do: {:error, :research_member_required}
end

defmodule JidoAI.Examples.Proposed.ResearchAgent.Ask do
  @moduledoc "Defines the typed research request and reply Signals."

  use Jido.Action,
    name: "proposed_research_ask",
    description: "Ask the proposed research Agent one question",
    schema: Zoi.object(%{query: Zoi.string() |> Zoi.min(1)}),
    output_schema:
      Zoi.object(%{
        answer: Zoi.string() |> Zoi.min(1),
        sources: Zoi.list(Zoi.string()),
        confidence: Zoi.number() |> Zoi.min(0) |> Zoi.max(1)
      })

  @impl Jido.Action
  def run(%{query: query}, context),
    do:
      Jido.AI.respond(context, query,
        reply: {JidoAI.Examples.Proposed.ResearchAgent.Agent, "examples.proposed.research.ask"}
      )
end

defmodule JidoAI.Examples.Proposed.ResearchAgent.Turn do
  @moduledoc "Runs and commits one complete research Session turn."

  alias JidoAI.Examples.Proposed.ResearchAgent.Ask

  use Jido.Action,
    name: "proposed_research_turn",
    description: "Generate and commit one structured research reply",
    schema: Ask.schema(),
    output_schema:
      Zoi.object(%{
        state:
          Zoi.object(%{
            session: Jido.Session.schema(),
            status: Zoi.enum(["idle", "ready"]),
            last_query: Zoi.string() |> Zoi.nullable(),
            last_delegated_query: Zoi.string() |> Zoi.nullable(),
            request_count: Zoi.integer() |> Zoi.min(0)
          }),
        reply: Ask.output_schema()
      })

  @impl Jido.Action
  def run(params, context) do
    with {:ok, _prepared} <- Jido.AI.Turn.prepare(context, state_key: :session),
         {:ok, answer} <- Ask.run(params, context),
         {:ok, %{state: state, reply: reply}} <-
           Jido.AI.Turn.complete(
             context,
             {JidoAI.Examples.Proposed.ResearchAgent.Agent, "examples.proposed.research.ask"},
             answer,
             state_key: :session
           ) do
      state = %{
        state
        | status: "ready",
          last_query: params.query,
          request_count: state.request_count + 1
      }

      {:ok, %{state: state, reply: reply}}
    end
  end
end

defmodule JidoAI.Examples.Proposed.ResearchAgent.Worker do
  @moduledoc "A core Jido child Agent used by the topology example."

  use Jido.Agent,
    name: "proposed_research_worker",
    description: "Process delegated research work"

  state do
    schema Zoi.object(%{
             jobs: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
             last_query: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil)
           })
  end

  routes do
    signal_source "/examples/proposed/research/worker"

    route "examples.proposed.research.work" do
      action %{query: query},
        name: "proposed_research_worker_handle",
        description: "Process delegated research work",
        schema: Zoi.object(%{query: Zoi.string() |> Zoi.min(1)}),
        context: context do
        state = %{
          context.agent_state
          | jobs: context.agent_state.jobs + 1,
            last_query: query
        }

        {:ok, state, [emit("examples.proposed.research.work.completed", %{query: query})]}
      end
    end
  end
end

defmodule JidoAI.Examples.Proposed.ResearchAgent.Agent do
  @moduledoc "A proposed kitchen-sink Agent that combines core Jido and Jido AI."

  alias JidoAI.Examples.Proposed.ResearchAgent.{
    Ask,
    ResearchFlow,
    SearchSources,
    Turn,
    ValidateRequest,
    Worker
  }

  use Jido.AI.Agent,
    name: "proposed_research_agent",
    description: "Show the current core Jido and Jido AI Agent DSL",
    id: "examples/proposed/research_agent",
    vsn: 1,
    metadata: %{
      category: "proposed",
      purpose: "kitchen_sink_research_example"
    }

  state do
    schema Zoi.object(%{
             session: Jido.Session.schema(),
             status: Zoi.enum(["idle", "ready"]) |> Zoi.default("idle"),
             last_query: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
             last_delegated_query: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
             request_count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)
           })
  end

  @impl Jido.Agent
  def initialize(state, _context) do
    {:ok,
     Map.put_new_lazy(state, :session, fn ->
       Jido.Session.new!(metadata: %{example: "proposed_research_agent"})
     end)}
  end

  ai do
    model :fast

    instructions """
    Answer the research question with clear evidence.
    Use the research tools when they help.
    Return an answer, at least one source, and a confidence value.
    """

    graph do
      step "model",
        action: Jido.AI.Actions.CallModel,
        params: input(:request)

      invoke "decision",
        decision: Jido.AI.Actions.InterpretOutcome,
        expander: Jido.AI.Flow.ReAct.ExpandDecision,
        params: result("model")

      output result("decision")
    end

    tools do
      action SearchSources,
        as: :search_sources,
        description: "Find deterministic local sources",
        timeout: 2_000

      flow ResearchFlow,
        as: :research_brief,
        description: "Search sources and compile a brief",
        timeout: 5_000
    end

    controls do
      timeout 30_000
      max_iterations 4
      max_model_calls 4
      max_tool_calls 6

      input ValidateRequest

      output %{output: output},
        name: "proposed_research_validate_output",
        description: "Require sources and a minimum confidence value",
        schema: Zoi.object(%{output: Ask.output_schema()}) do
        cond do
          output.sources == [] -> {:error, :sources_required}
          output.confidence < 0.5 -> {:error, :confidence_too_low}
          true -> {:ok, %{accepted: true}}
        end
      end
    end
  end

  routes do
    signal_source "/examples/proposed/research"

    route "examples.proposed.research.ask", Turn, as: :ask do
      state(from: output(:state))
      reply("examples.proposed.research.answered", from: output(:reply))
    end

    route "examples.proposed.research.work" do
      forward(to: agent(:worker))
    end

    route "examples.proposed.research.work.completed", as: :work_completed do
      action %{query: query},
        name: "proposed_research_record_delegated_work",
        description: "Record completed delegated research work",
        schema: Zoi.object(%{query: Zoi.string() |> Zoi.min(1)}),
        context: context do
        {:ok, %{context.agent_state | last_delegated_query: query}}
      end
    end
  end

  topology do
    agent :worker, Worker do
      initial_state %{jobs: 0}
    end

    connections do
      connect "examples.proposed.research.work.completed", from: :worker, to: :root
    end
  end
end

defmodule JidoAI.Examples.Proposed.ResearchAgent do
  @moduledoc "Builds the proposed research Agent with per-instance Session data."

  alias JidoAI.Examples.Proposed.ResearchAgent.Agent

  @doc "Returns the static Agent definition."
  def definition, do: Agent.definition()

  @doc "Builds one Agent instance with a fresh Session."
  def new(opts \\ []), do: Agent.instantiate(opts)
end
