defmodule ReqLLM.Providers.AnthropicEnvTest do
  use ExUnit.Case, async: true

  describe "environment variable extraction" do
    test "gets environment variable name from metadata" do
      # Since the provider is already loaded through DSL, we can test metadata access
      case ReqLLM.Provider.Registry.get_provider_metadata(:anthropic) do
        {:ok, metadata} ->
          env_vars = get_in(metadata, ["provider", "env"])
          assert env_vars == ["ANTHROPIC_API_KEY"]

        {:error, :provider_not_found} ->
          # Provider not loaded in test environment, that's okay
          # We can still test the JSON parsing logic directly
          metadata_path = "priv/models_dev/anthropic.json"
          assert File.exists?(metadata_path)

          {:ok, content} = File.read(metadata_path)
          {:ok, data} = Jason.decode(content)
          env_vars = get_in(data, ["provider", "env"])
          assert env_vars == ["ANTHROPIC_API_KEY"]
      end
    end

    test "generates correct kagi key from environment variable name" do
      env_var = "ANTHROPIC_API_KEY"
      kagi_key = String.downcase(env_var) |> String.to_atom()
      assert kagi_key == :anthropic_api_key
    end
  end
end
