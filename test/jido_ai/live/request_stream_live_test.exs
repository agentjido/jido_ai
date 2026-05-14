defmodule Jido.AI.Live.RequestStreamLiveTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Opt-in smoke coverage for request streaming against a live LLM provider.

      OPENAI_API_KEY=... \
      JIDO_LIVE_MODEL="openai:gpt-4o-mini" \
      mix test --include live --include flaky test/jido_ai/live/request_stream_live_test.exs
  """

  @moduletag :live
  @moduletag :flaky
  @moduletag timeout: 120_000

  @live_model System.get_env("JIDO_LIVE_MODEL", "openai:gpt-4o-mini")

  @required_env (case String.split(@live_model, ":", parts: 2) do
                   ["openai", _model] -> "OPENAI_API_KEY"
                   ["anthropic", _model] -> "ANTHROPIC_API_KEY"
                   ["google", _model] -> "GOOGLE_API_KEY"
                   ["openrouter", _model] -> "OPENROUTER_API_KEY"
                   ["xai", _model] -> "XAI_API_KEY"
                   ["groq", _model] -> "GROQ_API_KEY"
                   ["cerebras", _model] -> "CEREBRAS_API_KEY"
                   ["zai", _model] -> "ZAI_API_KEY"
                   _ -> nil
                 end)

  if is_nil(@required_env) do
    @moduletag skip: "JIDO_LIVE_MODEL must use a supported provider prefix for this smoke test; got #{@live_model}"
  end

  @required_key if is_binary(@required_env), do: System.get_env(@required_env), else: nil

  if is_binary(@required_env) and (@required_key == nil or @required_key == "") do
    @moduletag skip: "set #{@required_env} to run live LLM request streaming smoke test"
  end

  defmodule EchoTool do
    use Jido.Action,
      name: "echo",
      description: "Echoes text",
      schema: Zoi.object(%{text: Zoi.string()})

    def run(%{text: text}, _context), do: {:ok, %{text: text}}
  end

  defmodule LiveAgent do
    alias Jido.AI.Live.RequestStreamLiveTest.EchoTool

    use Jido.AI.Agent,
      name: "live_request_stream_agent",
      model: :fast,
      tools: [EchoTool],
      max_iterations: 2,
      max_tokens: 64,
      streaming: true,
      stream_timeout_ms: 60_000
  end

  setup_all do
    configure_model_alias()
    configure_provider_keys()

    if is_nil(Process.whereis(Jido)) do
      start_supervised!({Jido, name: Jido})
    end

    :ok
  end

  test "ask_stream/3 yields live ReAct events and await returns the final answer" do
    {:ok, pid} = Jido.AgentServer.start_link(agent: LiveAgent)
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

    assert {:ok, %{request: request, events: events}} =
             LiveAgent.ask_stream(
               pid,
               "Reply with exactly one lowercase word: pong",
               allowed_tools: [],
               llm_opts: [temperature: 0, max_tokens: 16],
               stream_timeout_ms: 60_000,
               stream_event_timeout_ms: 60_000
             )

    event_list = Enum.to_list(events)
    kinds = Enum.map(event_list, & &1.kind)

    assert event_list != []
    assert Enum.all?(event_list, &(&1.request_id == request.id))
    assert :request_started in kinds
    assert :llm_delta in kinds
    assert :llm_completed in kinds
    assert :request_completed in kinds

    streamed_text =
      event_list
      |> Enum.filter(&(&1.kind == :llm_delta))
      |> Enum.map_join(&to_string(&1.data[:delta] || &1.data["delta"] || ""))

    assert String.length(streamed_text) > 0

    assert {:ok, answer} = LiveAgent.await(request, timeout: 10_000)
    assert String.contains?(String.downcase(to_string(answer)), "pong")
  end

  defp live_model, do: @live_model

  defp configure_model_alias do
    aliases =
      :jido_ai
      |> Application.get_env(:model_aliases, %{})
      |> Map.put(:fast, live_model())

    Application.put_env(:jido_ai, :model_aliases, aliases)
  end

  defp configure_provider_keys do
    [
      openai_api_key: "OPENAI_API_KEY",
      anthropic_api_key: "ANTHROPIC_API_KEY",
      google_api_key: "GOOGLE_API_KEY",
      openrouter_api_key: "OPENROUTER_API_KEY",
      xai_api_key: "XAI_API_KEY",
      groq_api_key: "GROQ_API_KEY",
      cerebras_api_key: "CEREBRAS_API_KEY",
      zai_api_key: "ZAI_API_KEY"
    ]
    |> Enum.each(fn {config_key, env_key} ->
      case System.get_env(env_key) do
        key when is_binary(key) and key != "" ->
          Application.put_env(:req_llm, config_key, key)

        _missing ->
          :ok
      end
    end)
  end
end
