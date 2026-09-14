defmodule Jido.AI.Reasoning.ReAct.TokenTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.ReAct.{Config, State, Token}
  @insecure_default_secret "jido_ai_react_default_secret_change_me"

  defmodule TransformerA do
    def transform_request(request, _state, _config, _context), do: {:ok, request}
  end

  defmodule TransformerB do
    def transform_request(request, _state, _config, _context), do: {:ok, request}
  end

  test "defaults omitted model to resolved :fast alias" do
    config = Config.new(%{tools: %{}})

    assert config.model == Jido.AI.Models.resolve(:fast)
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

  test "request_transformer participates in config fingerprint" do
    config_a =
      Config.new(%{
        model: :capable,
        tools: %{},
        request_transformer: TransformerA,
        token_secret: "secret-a"
      })

    config_b =
      Config.new(%{
        model: :capable,
        tools: %{},
        request_transformer: TransformerB,
        token_secret: "secret-a"
      })

    state = State.new("hello", nil, request_id: "req_transformer", run_id: "run_transformer")
    token = Token.issue(state, config_a)

    assert {:error, :token_config_mismatch} = Token.decode(token, config_b)
  end

  test "fingerprint supports inline model specs" do
    config =
      Config.new(%{
        model: %{provider: :openai, id: "gpt-4o-mini", base_url: "http://localhost:4000/v1"},
        tools: %{},
        token_secret: "secret-a"
      })

    assert is_binary(Config.fingerprint(config))
  end

  test "rejects expired tokens" do
    config = Config.new(%{model: :capable, tools: %{}, token_secret: "secret-a", token_ttl_ms: 1})
    state = State.new("hello", nil, request_id: "req_4", run_id: "run_4")
    token = Token.issue(state, config)

    Process.sleep(10)

    assert {:error, :token_expired} = Token.decode(token, config)
  end

  test "rejects the known insecure default token secret" do
    assert_raise ArgumentError, ~r/insecure ReAct token secret rejected/, fn ->
      Config.new(%{model: :capable, tools: %{}, token_secret: @insecure_default_secret})
    end
  end

  test "uses stable ephemeral token secret when explicit secret is blank" do
    config_a = Config.new(%{model: :capable, tools: %{}, token_secret: ""})
    config_b = Config.new(%{model: :capable, tools: %{}, token_secret: ""})

    assert is_binary(config_a.token.secret)
    assert config_a.token.secret == config_b.token.secret
    refute config_a.token.secret == @insecure_default_secret
  end

  test "mark_cancelled replaces incompatible terminal data and keeps the reason" do
    config = Config.new(%{model: :capable, tools: %{}, token_secret: "secret-a"})

    state =
      State.new("hello", nil, request_id: "req_cancel", run_id: "run_cancel")
      |> State.put_status(:failed)
      |> State.put_result("old result")
      |> State.put_error(:old_error)
      |> Map.put(:termination_reason, :failed)

    token = Token.issue(state, config)

    assert {:ok, cancelled_token} = Token.mark_cancelled(token, config, :user_cancelled)
    assert {:ok, cancelled, _payload} = Token.decode_state(cancelled_token, config)
    assert cancelled.status == :cancelled
    assert cancelled.result == nil
    assert cancelled.error == :user_cancelled
    assert cancelled.termination_reason == :cancelled
  end
end
