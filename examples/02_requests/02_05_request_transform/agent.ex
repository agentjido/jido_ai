defmodule JidoAI.Examples.RequestTransform.Transform do
  @moduledoc "Uses a request resource to supply fresh model options for each call."
  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer
  alias JidoAI.Examples.MockLLM

  def transform_request(
        request,
        %Jido.AI.Reasoning.ReAct.State{} = state,
        %Jido.AI.Reasoning.ReAct.Config{} = config,
        context
      ) do
    n = Agent.get_and_update(context.calls, &{&1 + 1, &1 + 1})

    send(
      context.observer,
      {:transformed, n, request, state.request_id, state.run_id, context.query}
    )

    send(context.observer, {:transform_state, n, state})
    mode = Map.get(context, :transform_mode, :refresh)

    cond do
      mode == :error && n > 1 ->
        {:error, :credentials_unavailable}

      mode == :invalid && n > 1 ->
        {:ok, %{messages: "invalid"}}

      mode == :gate ->
        {:ok, %{tools: if(n == 1, do: request.tools, else: %{}), llm_opts: [tools: [:must_be_removed]]}}

      true ->
        http =
          Keyword.get(request.llm_opts, :req_http_options, [])
          |> Keyword.put(:headers, [{"x-credential-version", Integer.to_string(n)}])

        overrides = %{llm_opts: [req_http_options: http], tools: config.tools}

        overrides =
          if n > 1 && mode == :refresh do
            Map.merge(overrides, %{
              model: MockLLM.model("gpt-4.1-mini"),
              llm_opts: [req_http_options: http, stream: true, tool_choice: :auto],
              messages: [
                %{role: :system, content: "Use this request's repair policy."},
                %{role: :user, content: "Normalize ticket #{n}."}
              ]
            })
          else
            overrides
          end

        {:ok, overrides}
    end
  end
end

defmodule JidoAI.Examples.RequestTransform.ModelControl do
  @moduledoc "Checks the model selected by the transformer."
  @behaviour Jido.AI.Control
  def check(request, context) do
    model_id = if is_map(request.model), do: request.model.id, else: to_string(request.model)
    send(context.observer, {:model_checked, model_id})

    if context[:reject_alternate] && model_id == "gpt-4.1-mini",
      do: {:error, :model_not_allowed},
      else: :ok
  end
end

defmodule JidoAI.Examples.RequestTransform.Repair do
  @moduledoc "A configured repair callback that returns a value for schema validation."
  def repair(_output, _raw, _reason), do: {:ok, %{answer: "three-argument fallback"}}

  def repair(output, raw, reason, context) do
    n = Agent.get_and_update(context.repairs, &{&1 + 1, &1 + 1})
    send(context.observer, {:repaired, n, output.repair_fun, raw, reason, context})

    if Map.get(context, :invalid_repair, false),
      do: {:ok, %{answer: 42}},
      else: {:ok, %{answer: "Callback result"}}
  end
end

defmodule JidoAI.Examples.RequestTransform.Agent do
  @moduledoc "The Agent uses the same transformer for normal and repair requests."
  use Jido.AI.Agent,
    name: "request_transform_agent",
    tools: [JidoAI.Examples.RequestScope.Echo],
    model: :example,
    streaming: true,
    request_transformer: JidoAI.Examples.RequestTransform.Transform,
    output: [schema: Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)}), retries: 2]
end

defmodule JidoAI.Examples.RequestTransform.CallbackAgent do
  @moduledoc "A trusted callback repairs output after request transformation."
  use Jido.AI.Agent,
    name: "repair_callback_agent",
    tools: [JidoAI.Examples.RequestScope.Echo],
    model: :example,
    streaming: false,
    request_transformer: JidoAI.Examples.RequestTransform.Transform,
    output: [
      schema: Zoi.object(%{answer: Zoi.string()}),
      retries: 2,
      repair_fun: {JidoAI.Examples.RequestTransform.Repair, :repair}
    ]
end

defmodule JidoAI.Examples.RequestTransform.NativeAgent do
  @moduledoc "The core Agent DSL uses the same transformer and repair callback."
  use Jido.Agent, name: "native_request_transform", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.map() |> Zoi.default(%{})})

    ai :assistant do
      models do
        model(:answer, :example)
      end

      reasoning :react do
        model(:answer)
        request_transformer(JidoAI.Examples.RequestTransform.Transform)
      end

      controls do
        model(JidoAI.Examples.RequestTransform.ModelControl)
        max_model_calls(2)
      end

      tools do
        action JidoAI.Examples.RequestScope.Echo, as: :scope_echo
      end

      result(Zoi.object(%{answer: Zoi.string()}),
        into: :reply,
        max_repairs: 2,
        repair_fun: &JidoAI.Examples.RequestTransform.Repair.repair/4
      )
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end

  def source do
    %{
      id: :assistant,
      models: %{answer: :example},
      reasoning: %{
        method: :react,
        model: :answer,
        request_transformer: JidoAI.Examples.RequestTransform.Transform
      },
      controls: %{model: [JidoAI.Examples.RequestTransform.ModelControl], max_model_calls: 2},
      tools: [
        %{
          name: "scope_echo",
          target: JidoAI.Examples.RequestScope.Echo,
          description: "scope_echo"
        }
      ],
      result: %{
        schema: Zoi.object(%{answer: Zoi.string()}),
        into: :reply,
        max_repairs: 2,
        repair_fun: &JidoAI.Examples.RequestTransform.Repair.repair/4
      },
      routes: ["ai.ask"]
    }
  end

  def base do
    Jido.Agent.new!(
      name: "native_request_transform",
      module: __MODULE__,
      vsn: vsn(),
      schema: Zoi.object(%{reply: Zoi.map() |> Zoi.default(%{})})
    )
  end
end
