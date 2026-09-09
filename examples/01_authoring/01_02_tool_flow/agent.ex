defmodule JidoAI.Examples.ToolFlow.Multiply do
  @moduledoc false
  use Jido.Action,
    name: "v3_example_multiply",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()}, coerce: true)

  def run(%{a: a, b: b}, context) do
    send(context.observer, {:tool_executed, a, b})
    {:ok, %{value: a * b}}
  end
end

defmodule JidoAI.Examples.ToolFlow.Quote do
  @moduledoc "An ordinary nested Flow can be a model-callable tool."
  use Jido.Flow,
    name: "v3_example_quote",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  flow do
    step "price", action: JidoAI.Examples.ToolFlow.Multiply, params: input()
    output result("price")
  end
end

defmodule JidoAI.Examples.ToolFlow.Select do
  @moduledoc "Validate the full selected batch before any tool starts."
  use Jido.Action, name: "v3_example_select", schema: JidoAI.Examples.Schema.prompt()
  alias JidoAI.Examples.ToolFlow.{Multiply, Quote}

  def tools do
    for name <- ["multiply", "quote"] do
      ReqLLM.Tool.new!(
        name: name,
        description: "Multiply two integers",
        parameter_schema: Multiply.schema(),
        callback: fn _ -> raise "Tool execution belongs to Jido.Exec" end
      )
    end
  end

  def run(%{query: query}, context) do
    opts = Keyword.put(context.model_options, :tools, tools())

    with {:ok, response} <- ReqLLM.generate_text(context.model, query, opts),
         {:ok, calls} <- admit(ReqLLM.Response.tool_calls(response)) do
      {:ok, %{response: response, calls: calls}}
    end
  end

  defp admit(calls) when length(calls) in 1..4 do
    Enum.reduce_while(calls, {:ok, []}, fn raw, {:ok, admitted} ->
      call = ReqLLM.ToolCall.to_map(raw)
      target = %{"multiply" => Multiply, "quote" => Quote}[call.name]

      with true <- not is_nil(target),
           false <- Enum.any?(admitted, &(&1.id == call.id)),
           {:ok, args} <- Zoi.parse(Multiply.schema(), call.arguments) do
        {:cont, {:ok, admitted ++ [Map.merge(call, %{target: target, arguments: args})]}}
      else
        _ -> {:halt, invalid()}
      end
    end)
  end

  defp admit(_), do: invalid()
  defp invalid, do: {:error, Jido.Action.Error.validation_error("invalid tool batch")}
end

defmodule JidoAI.Examples.ToolFlow.Execute do
  @moduledoc false
  use Jido.Action, name: "v3_example_execute_tool"

  def run(call, context) do
    with {:ok, output} <-
           Jido.Exec.run(call.target, call.arguments, Map.take(context, [:observer]), timeout: 1_000) do
      {:ok, %{id: call.id, name: call.name, output: output}}
    end
  end
end

defmodule JidoAI.Examples.ToolFlow.Finish do
  @moduledoc false
  use Jido.Action, name: "v3_example_tool_finish"

  def run(%{response: response, results: results}, context) do
    messages =
      Enum.map(results, &ReqLLM.Context.tool_result(&1.id, &1.name, Jason.encode!(&1.output)))

    with {:ok, continued} <-
           ReqLLM.Context.append_tool_exchange(response.context, response, messages),
         {:ok, final} <- ReqLLM.generate_text(context.model, continued, context.model_options) do
      {:ok, %{answer: ReqLLM.Response.text(final)}}
    end
  end
end

defmodule JidoAI.Examples.ToolFlow.Flow do
  @moduledoc "Model selection, batch admission, Map execution, and real model continuation."
  use Jido.Flow, name: "v3_example_tool_flow", schema: JidoAI.Examples.Schema.prompt()
  alias JidoAI.Examples.ToolFlow

  flow do
    step "select", action: ToolFlow.Select, params: input()
    map "tools", collection: result("select", :calls), action: ToolFlow.Execute, params: item()

    step "answer",
      action: ToolFlow.Finish,
      params: %{response: result("select", :response), results: result("tools")}

    step "candidate", action: JidoAI.Examples.Commit, params: result("answer")
    output result("candidate")
  end
end

defmodule JidoAI.Examples.ToolFlow.Agent do
  @moduledoc "01_02: Real Action and Flow tools with correlated model messages."
  use Jido.Agent, name: "v3_example_tools_agent"

  agent do
    schema JidoAI.Examples.Schema.state()
  end

  routes do
    route "ai.ask", JidoAI.Examples.ToolFlow.Flow
  end
end
