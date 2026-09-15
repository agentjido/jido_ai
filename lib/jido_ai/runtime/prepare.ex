defmodule Jido.AI.Runtime.Prepare do
  @moduledoc false
  use Jido.Action, name: "ai_prepare"
  alias Jido.AI.{Control, Models, Profile}

  @impl Jido.Action
  def run(params, context), do: Jido.AI.Error.capture(fn -> execute(params, context) end)

  defp execute(%{profile_id: id, query: query}, context) do
    with %Profile{} = profile <- get_in(context, [:jido_ai_profiles, id]),
         deadline = System.monotonic_time(:millisecond) + profile.controls.timeout,
         :ok <- Control.check(profile, :input, %{query: query}, context, deadline),
         {:ok, profile} <-
           Jido.AI.Instructions.resolve(profile, %{query: query}, context, deadline),
         {:ok, profile} <- Jido.AI.ModelRouter.select(profile, %{query: query}, context),
         {:ok, profile, adaptive} <- Jido.AI.Reasoning.select(profile, query),
         {:ok, output} <- Profile.output_contract(profile.result),
         {:ok, history} <- Jido.AI.Orchestration.Transcript.read(context.agent_state, profile),
         {:ok, history_messages} <- Jido.AI.Model.Messages.messages(history) do
      entry = profile.models[profile.reasoning.model]
      model = Models.resolve(entry.model)
      runtime_options = get_in(context, [:ai, id, :options]) || []

      options =
        Jido.AI.Reasoning.generation(profile, entry.generation)
        |> Jido.AI.Model.Options.merge_http_options(runtime_options[:req_http_options])
        |> Keyword.merge(Keyword.delete(runtime_options, :req_http_options))
        |> then(&Jido.AI.Model.Options.merge([], &1, model))

      instructions =
        Jido.AI.Reasoning.instructions(profile, output)
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join("\n\n")

      messages = if instructions == "", do: [], else: [ReqLLM.Context.system(instructions)]

      messages =
        messages ++
          history_messages ++
          [
            Jido.AI.Model.Messages.put_refs(
              ReqLLM.Context.user(Jido.AI.Reasoning.query(profile, query)),
              Jido.AI.Orchestration.Transcript.request_refs(context)
            )
          ]

      refs =
        case context[:jido_ai_request_record] do
          nil -> %{}
          record -> Jido.AI.Orchestration.Transcript.refs(record, context.jido_ai_input_source)
        end

      state = %{
        profile: profile,
        effect_plan: Jido.AI.Effects.Candidate.new(context.agent_state),
        model: model,
        options: options,
        messages: ReqLLM.Context.new(messages),
        output: output,
        deadline: deadline,
        history_delta: Jido.AI.Orchestration.Transcript.query(query, refs)
      }

      state = if adaptive, do: Map.put(state, :adaptive, adaptive), else: state

      with {:ok, state} <- Jido.AI.Runtime.State.new(state),
           {:ok, state} <- Jido.AI.Runtime.Checkpoint.restore(state, context),
           {:ok, state} <- Jido.AI.Reasoning.prepare(state, query),
           {:ok, state} <- Jido.AI.Runtime.State.validate(state),
           :ok <- Jido.AI.Orchestration.publish_selection(context, adaptive, deadline),
           do: {:ok, state}
    else
      {:error, _} = error -> error
      _ -> Profile.error("profile", "No trusted profile binding")
    end
  end
end
