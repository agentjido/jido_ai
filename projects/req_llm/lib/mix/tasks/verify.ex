defmodule Mix.Tasks.ReqLlm.Verify do
  @moduledoc """
  Verify advertised capabilities of a model or all models from a provider.

  ## Usage

      mix req_llm.verify anthropic:claude-3-sonnet
      mix req_llm.verify anthropic --only generate_text --format debug
      mix req_llm.verify openai:gpt-4o --timeout 30000

  ## Options

    * `--timeout` - Request timeout in milliseconds (default: 10000)
    * `--only` - Comma-separated list of capability IDs to test
    * `--format` - Output format: pretty, json, debug (default: pretty)
    * `--fail-fast` - Stop on first failure

  """
  use Mix.Task

  @shortdoc "Verify advertised capabilities of a model"

  @impl Mix.Task
  def run(argv) do
    {opts, args, invalid} =
      OptionParser.parse(
        argv,
        strict: [
          timeout: :integer,
          only: :string,
          format: :string,
          fail_fast: :boolean,
          help: :boolean
        ],
        aliases: [
          t: :timeout,
          o: :only,
          f: :format,
          h: :help
        ]
      )

    cond do
      opts[:help] ->
        show_help()

      invalid != [] ->
        Mix.shell().error("Invalid options: #{inspect(invalid)}")
        System.halt(1)

      length(args) != 1 ->
        Mix.shell().error("Expected exactly one model ID or provider argument")
        show_help()
        System.halt(1)

      true ->
        input = List.first(args)

        # Convert --only string to list if provided
        opts =
          case Keyword.get(opts, :only) do
            nil -> opts
            only_string -> Keyword.put(opts, :only, String.split(only_string, ","))
          end

        # Ensure the application is started
        Mix.Task.run("app.start")

        case verify_input(input, opts) do
          :ok ->
            Mix.shell().info("✅ All capabilities verified successfully")
            System.halt(0)

          :error ->
            Mix.shell().error("❌ One or more capabilities failed verification")
            System.halt(1)
        end
    end
  end

  # Determines whether the input is a provider-only string or a full model spec
  defp verify_input(input, opts) do
    case String.contains?(input, ":") do
      true ->
        # Full model spec like "anthropic:claude-3-sonnet"
        ReqLLM.Capability.verify(input, opts)

      false ->
        # Provider-only string like "anthropic"
        verify_provider_models(input, opts)
    end
  end

  # Verifies all models for a given provider
  defp verify_provider_models(provider_string, opts) do
    case load_provider_models(provider_string) do
      {:ok, model_ids} ->
        Mix.shell().info("Found #{length(model_ids)} models for provider #{provider_string}")
        Mix.shell().info("Testing models: #{Enum.join(model_ids, ", ")}")

        results =
          model_ids
          |> Enum.map(fn model_id ->
            Mix.shell().info("\n--- Verifying #{model_id} ---")

            case ReqLLM.Capability.verify(model_id, opts) do
              :ok ->
                Mix.shell().info("✅ #{model_id} passed")
                :ok

              :error ->
                Mix.shell().error("❌ #{model_id} failed")
                :error
            end
          end)

        case Enum.all?(results, &(&1 == :ok)) do
          true -> :ok
          false -> :error
        end

      {:error, reason} ->
        Mix.shell().error("❌ #{reason}")
        :error
    end
  end

  # Loads all model IDs for a given provider
  defp load_provider_models(provider_string) do
    priv_dir = Application.app_dir(:req_llm, "priv")
    provider_path = Path.join([priv_dir, "models_dev", "#{provider_string}.json"])

    case File.read(provider_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"models" => models}} when is_list(models) ->
            model_ids =
              models
              |> Enum.map(fn model -> "#{provider_string}:#{model["id"]}" end)
              |> Enum.filter(&(&1 != "#{provider_string}:"))

            case model_ids do
              [] -> {:error, "No models found for provider #{provider_string}"}
              ids -> {:ok, ids}
            end

          {:ok, _} ->
            {:error, "Invalid provider file format for #{provider_string}"}

          {:error, decode_error} ->
            {:error, "Failed to decode provider file: #{inspect(decode_error)}"}
        end

      {:error, :enoent} ->
        {:error, "Provider #{provider_string} not found"}

      {:error, file_error} ->
        {:error, "Failed to read provider file: #{inspect(file_error)}"}
    end
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix req_llm.verify MODEL_ID|PROVIDER [OPTIONS]

    Verify that a model or all models from a provider can perform their advertised capabilities.

    Arguments:
      MODEL_ID    The model identifier (e.g., anthropic:claude-3-sonnet)
      PROVIDER    The provider name to test all models (e.g., anthropic)

    Options:
      --timeout, -t    Request timeout in milliseconds (default: 10000)
      --only, -o       Comma-separated list of capability IDs to test
      --format, -f     Output format: pretty, json, debug (default: pretty)
      --fail-fast      Stop on first failure
      --help, -h       Show this help

    Examples:
      mix req_llm.verify anthropic:claude-3-sonnet
      mix req_llm.verify anthropic --only generate_text --format debug
      mix req_llm.verify openai:gpt-4o --timeout 30000
    """)
  end
end
