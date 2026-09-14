defmodule Jido.AI.CLI.EphemeralAgent do
  @moduledoc false

  def create(module_name, attrs) do
    method = Keyword.fetch!(attrs, :method)
    model = Keyword.get(attrs, :model, :fast)

    tools =
      Enum.map(Keyword.get(attrs, :tools, []), fn target ->
        %{
          target: target,
          forward_context: :all,
          timeout: 15_000,
          max_retries: 1,
          retry_backoff: 200
        }
      end)

    profile =
      Jido.AI.profile!(%{
        id: :assistant,
        instructions: Keyword.get(attrs, :instructions) || default_instructions(method),
        models: %{
          answer: %{
            model: model,
            generation: Keyword.get(attrs, :generation, [])
          }
        },
        reasoning: %{
          method: method,
          model: :answer,
          options: Keyword.get(attrs, :reasoning_options, %{})
        },
        controls: %{
          max_iterations: Keyword.get(attrs, :max_iterations, :method_default),
          max_model_calls: Keyword.get(attrs, :max_model_calls, :method_default),
          max_tool_calls: Keyword.get(attrs, :max_tool_calls, :method_default),
          timeout: Keyword.get(attrs, :timeout, 60_000)
        },
        tools: tools,
        requests: %{
          mode: :session,
          streaming: Keyword.get(attrs, :streaming, true),
          steering: method == :react
        },
        memory: %{history: if(Jido.AI.Reasoning.single_pass?(method), do: nil, else: :messages)},
        result: %{schema: nil, into: :last_result}
      })

    schema =
      Zoi.object(%{
        last_result: Zoi.any() |> Zoi.default(nil),
        messages: Zoi.list(Zoi.map()) |> Zoi.default([])
      })

    {:ok, definition} =
      Jido.AI.Authoring.lower(
        %{
          name: Keyword.fetch!(attrs, :name),
          description: Keyword.get(attrs, :description),
          schema: schema,
          routes: [{"ai.#{Jido.AI.Reasoning.label(method)}.query", Jido.AI.Authoring.ai(:assistant)}]
        },
        [profile]
      )

    options =
      definition
      |> Map.from_struct()
      |> Map.drop([:id, :state, :module, :vsn])
      |> Enum.to_list()

    contents =
      quote do
        use Jido.Agent, unquote(Macro.escape(options))

        def ask(server, query, opts \\ []),
          do: Jido.AI.Agent.Interface.ask(__MODULE__, server, query, opts)

        def ask_sync(server, query, opts \\ []),
          do: Jido.AI.Agent.Interface.ask_sync(__MODULE__, server, query, opts)

        def ask_stream(server, query, opts \\ []),
          do: Jido.AI.Agent.Interface.ask_stream(__MODULE__, server, query, opts)

        def await(request, opts \\ []), do: Jido.AI.Request.await(request, opts)
        def cancel(server, opts \\ []), do: Jido.AI.Agent.Interface.cancel(server, opts)
      end

    Module.create(module_name, contents, Macro.Env.location(__ENV__))
    module_name
  end

  defp default_instructions(method) do
    cond do
      Jido.AI.Reasoning.Linear.linear?(method) -> Jido.AI.Reasoning.Linear.default_prompt(method)
      method == :react -> Jido.AI.Reasoning.react_prompt()
      true -> nil
    end
  end
end
