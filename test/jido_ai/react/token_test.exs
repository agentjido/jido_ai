defmodule Jido.AI.Reasoning.ReAct.TokenTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.ReAct.{Config, State, Token}
  @legacy_insecure_secret "jido_ai_react_default_secret_change_me"

  test "defaults omitted model to resolved :fast alias" do
    config = Config.new(%{tools: %{}})

    assert config.model == Jido.AI.resolve_model(:fast)
  end

  test "issues and decodes checkpoint tokens" do
    config =
      Config.new(%{
        model: :capable,
        tools: %{},
        token_secret: "secret-a"
      })

    state = State.new("hello", config.system_prompt, request_id: "req_1", run_id: "run_1")

    token = Token.issue(state, config)
    assert is_binary(token)
    assert String.starts_with?(token, "rt2.")

    assert {:ok, payload} = Token.decode(token, config)
    assert payload.v == 2
    assert payload.iss == "jido_ai/react"
    assert payload.run_id == "run_1"
    assert payload.request_id == "req_1"
  end

  test "rejects tampered tokens" do
    config = Config.new(%{model: :capable, tools: %{}, token_secret: "secret-a"})
    state = State.new("hello", nil, request_id: "req_2", run_id: "run_2")
    token = Token.issue(state, config)

    tampered = token <> "x"
    assert {:error, :invalid_token_signature} = Token.decode(tampered, config)
  end

  test "rejects config fingerprint mismatches" do
    config_a = Config.new(%{model: :capable, tools: %{}, token_secret: "secret-a"})
    config_b = Config.new(%{model: :fast, tools: %{}, token_secret: "secret-a"})

    state = State.new("hello", nil, request_id: "req_3", run_id: "run_3")
    token = Token.issue(state, config_a)

    assert {:error, :token_config_mismatch} = Token.decode(token, config_b)
  end

  test "rejects expired tokens" do
    config = Config.new(%{model: :capable, tools: %{}, token_secret: "secret-a", token_ttl_ms: 1})
    state = State.new("hello", nil, request_id: "req_4", run_id: "run_4")
    token = Token.issue(state, config)

    Process.sleep(10)

    assert {:error, :token_expired} = Token.decode(token, config)
  end

  test "rejects insecure legacy default token secret" do
    assert_raise ArgumentError, ~r/insecure ReAct token secret rejected/, fn ->
      Config.new(%{model: :capable, tools: %{}, token_secret: @legacy_insecure_secret})
    end
  end

  test "uses stable ephemeral token secret when explicit secret is blank" do
    config_a = Config.new(%{model: :capable, tools: %{}, token_secret: ""})
    config_b = Config.new(%{model: :capable, tools: %{}, token_secret: ""})

    assert is_binary(config_a.token.secret)
    assert config_a.token.secret == config_b.token.secret
    refute config_a.token.secret == @legacy_insecure_secret
  end

  test "rejects legacy token state payloads that still include thread key" do
    config = Config.new(%{model: :capable, tools: %{}, token_secret: "secret-a"})
    state = State.new("hello", nil, request_id: "req_legacy", run_id: "run_legacy")
    now = System.system_time(:millisecond)

    payload = %{
      v: 2,
      iss: "jido_ai/react",
      run_id: state.run_id,
      request_id: state.request_id,
      iat_ms: now,
      exp_ms: nil,
      config_fingerprint: Config.fingerprint(config),
      state: %{
        context: state.context,
        thread: state.context
      }
    }

    token = forge_token(payload, config.token.secret)
    assert {:error, :legacy_token_state} = Token.decode(token, config)
  end

  test "state checkpoint restore hard-fails for legacy thread shape" do
    context = Jido.AI.Context.new() |> Jido.AI.Context.append_user("hello")

    assert {:error, :legacy_thread_checkpoint} =
             State.from_checkpoint_map(%{
               run_id: "run_legacy",
               request_id: "req_legacy",
               status: :running,
               thread: context
             })
  end

  defp forge_token(payload, secret) do
    payload_bin = :erlang.term_to_binary(payload)
    signature = :crypto.mac(:hmac, :sha256, secret, payload_bin)

    "rt2." <>
      Base.url_encode64(payload_bin, padding: false) <>
      "." <>
      Base.url_encode64(signature, padding: false)
  end
end
