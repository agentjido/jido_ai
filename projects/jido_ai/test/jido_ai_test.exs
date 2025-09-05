defmodule Jido.AITest do
  use ExUnit.Case, async: true
  use Jido.AI.TestMacros
  use ExUnitProperties

  import Jido.AI.Test.Fixtures.ModelFixtures
  import Jido.AI.TestSupport.Assertions
  import Mimic

  alias Jido.AI
  alias Jido.AI.Error.API.Request
  alias Jido.AI.Provider.OpenAI
  alias Jido.AI.Test.FakeProvider
  alias Kagi

  doctest Jido.AI

  setup :verify_on_exit!

  setup do
    copy(Kagi)
    # Register providers for testing
    Jido.AI.Provider.Registry.register(:fake, FakeProvider)
    Jido.AI.Provider.Registry.register(:openai, OpenAI)

    on_exit(fn ->
      Jido.AI.Provider.Registry.clear()
      Jido.AI.Provider.Registry.initialize()
    end)

    :ok
  end

  describe "api_key/1" do
    test "returns nil when no key configured" do
      stub(Kagi, :get, fn _, _, _ -> nil end)
      assert AI.api_key(:openai_api_key) == nil
    end

    test "returns key when available (atom)" do
      stub(Kagi, :get, fn
        Kagi, :openai_api_key, nil -> "provider-key"
      end)

      assert AI.api_key(:openai_api_key) == "provider-key"
    end

    test "returns key when available (string)" do
      stub(Kagi, :get, fn
        "anthropic_api_key", nil -> "anthropic-key"
      end)

      assert AI.api_key("anthropic_api_key") == "anthropic-key"
    end

    table_test(
      "handles case-insensitive string keys",
      [
        "OPENAI_API_KEY",
        "OpenAI_API_Key",
        "openai_api_key"
      ],
      fn key ->
        stub(Kagi, :get, fn
          "openai_api_key", nil -> "case-insensitive-key"
        end)

        assert AI.api_key(key) == "case-insensitive-key"
      end
    )
  end

  describe "provider/1" do
    test "returns provider module from registry" do
      provider_module = assert_ok(AI.provider(:fake))
      assert provider_module == FakeProvider
    end

    test "returns error for unknown provider" do
      assert {:error, :not_found} = AI.provider(:unknown)
    end
  end

  describe "list_keys/0" do
    test "delegates to keyring" do
      stub(Kagi, :list, fn Kagi -> ["key1", "key2"] end)
      assert AI.list_keys() == ["key1", "key2"]
    end
  end

  describe "model/1" do
    test "accepts string format" do
      stub(Kagi, :get, fn _, _, default -> default end)

      model = assert_ok(AI.model("fake:fake-model"))
      assert model.provider == :fake
      assert model.model == "fake-model"
    end

    test "accepts tuple format" do
      stub(Kagi, :get, fn _, _, default -> default end)

      model = assert_ok(AI.model({:fake, model: "fake-model", temperature: 0.8}))
      assert model.provider == :fake
      assert model.model == "fake-model"
      assert model.temperature == 0.8
    end

    test "accepts struct format" do
      model_struct = gpt4()
      returned_model = assert_ok(AI.model(model_struct))
      assert returned_model == model_struct
    end

    test "handles Model struct directly in text generation" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      model_struct = fake(model: "test-model", temperature: 0.5)

      result = assert_ok(AI.generate_text(model_struct, "hello"))
      assert result =~ "test-model"
    end

    table_test(
      "returns error for invalid formats",
      [
        {123, "Invalid model specification"},
        {"unknown:model", "Unknown provider: unknown"}
      ],
      fn {invalid_spec, expected_error} ->
        assert {:error, ^expected_error} = AI.model(invalid_spec)
      end
    )
  end

  describe "text generation" do
    test "generate_text works with options" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      model = {:fake, model: "fake-model", temperature: 0.3}
      result = assert_ok(AI.generate_text(model, "hello", max_tokens: 50))

      assert result =~ "fake-model"
      assert result =~ "hello"
      assert result =~ "temperature: 0.3"
      assert result =~ "max_tokens: 50"
    end

    test "generate_text works with system_prompt option" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      model = {:fake, model: "fake-model"}
      result = assert_ok(AI.generate_text(model, "hello", system_prompt: "You are helpful"))

      assert result =~ "system:You are helpful:"
      assert result =~ "fake-model"
      assert result =~ "hello"
    end

    test "stream_text returns chunks" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      stream = assert_ok(AI.stream_text({:fake, model: "fake-model"}, "hello"))
      assert Enum.to_list(stream) == ["chunk_1", "chunk_2", "chunk_3"]
    end

    test "stream_text works with system_prompt option" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      stream = assert_ok(AI.stream_text({:fake, model: "fake-model"}, "hello", system_prompt: "You are helpful"))
      assert Enum.to_list(stream) == ["chunk_1", "chunk_2", "chunk_3"]
    end

    test "propagates provider errors" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      defmodule ErrorProvider do
        def api_url, do: "https://error.test/v1"
        def generate_text(_, _, _), do: {:error, %Request{reason: "API Error"}}
        def stream_text(_, _, _), do: {:error, %Request{reason: "Stream Error"}}
        def provider_info, do: %{id: :error_provider, env: []}
      end

      Jido.AI.Provider.Registry.register(:error_provider, ErrorProvider)

      model = {:error_provider, model: "test"}
      assert {:error, %Request{}} = AI.generate_text(model, "hello")
      assert {:error, %Request{}} = AI.stream_text(model, "hello")
    end

    test "handles invalid model specs" do
      error = "Invalid model specification. Expected format: 'provider:model'"
      assert {:error, ^error} = AI.generate_text("invalid", "hello")
      assert {:error, ^error} = AI.stream_text("invalid", "hello")
    end

    test "options merge correctly" do
      stub(Kagi, :get, fn _, _, _ -> nil end)

      model = {:fake, model: "fake-model", temperature: 0.3, max_tokens: 100}
      result = assert_ok(AI.generate_text(model, "hello", max_tokens: 200, top_p: 0.9))

      assert result =~ "temperature: 0.3"
      assert result =~ "max_tokens: 200"
      assert result =~ "top_p: 0.9"
    end
  end

  describe "config/2" do
    test "handles nested config with non-api_key fallback" do
      # This should hit line 118 (default for non-api_key nested configs)
      result = AI.config([:openai, :some_other_key], "default_value")
      assert result == "default_value"
    end

    test "handles nested config in keyword list with non-api_key fallback" do
      # Set up application config with keyword list
      Application.put_env(:jido_ai, :openai, base_url: "https://api.openai.com")

      # This should hit line 136 (default for non-api_key in keyword list)
      result = AI.config([:openai, :some_other_key], "fallback_value")
      assert result == "fallback_value"

      # Clean up
      Application.delete_env(:jido_ai, :openai)
    end

    test "handles config with non-list main value" do
      # Set up application config with non-list value
      Application.put_env(:jido_ai, :test_key, "string_value")

      # This should hit line 142 (_main -> default)
      result = AI.config([:test_key, :nested], "default_val")
      assert result == "default_val"

      # Clean up
      Application.delete_env(:jido_ai, :test_key)
    end
  end

  describe "configuration integration" do
    test "uses keyring for api_key lookup" do
      stub(Kagi, :get, fn
        Kagi, :fake_api_key, nil -> "fake-secret"
        _, _, default -> default
      end)

      model = {:fake, model: "fake-model"}

      result = assert_ok(AI.generate_text(model, "hello"))
      assert result =~ "api_key: \"fake-secret\""
    end
  end

  describe "error handling" do
    test "handles provider not found gracefully" do
      assert {:error, "Unknown provider: nonexistent"} = AI.model("nonexistent:model")
    end

    table_test(
      "handles malformed model specs",
      [
        {nil, "Invalid model specification"},
        {123, "Invalid model specification"},
        {[], "Invalid model specification"},
        {%{invalid: "struct"}, "Invalid model specification"},
        {{"not_an_atom", model: "test"}, "Invalid model specification"}
      ],
      fn {spec, expected_error} ->
        assert {:error, ^expected_error} = AI.model(spec)
      end
    )
  end

  describe "property-based tests" do
    property "config/2 returns defaults when no config set" do
      check all(
              default <-
                StreamData.one_of([
                  StreamData.string(:alphanumeric),
                  StreamData.integer(),
                  StreamData.boolean()
                ])
            ) do
        stub(Kagi, :get, fn _keyring, _key, default -> default end)

        result = AI.config([:test, :key], default)
        assert result == default
      end
    end
  end
end
