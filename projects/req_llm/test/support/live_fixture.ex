defmodule ReqLLM.Test.LiveFixture do
  @moduledoc """
  Helper for tests that can run against live APIs or cached fixtures.

  Set LIVE=true to run against live APIs and capture new fixtures.
  Otherwise, tests use cached fixtures for fast, reliable testing.
  """

  require Logger

  @fixtures_base_dir Path.join([__DIR__, "fixtures"])

  @doc """
  Run a test function either live or against fixtures with provider-specific paths.

  ## Examples

      test "basic generation" do
        use_fixture :anthropic, "basic_generation", fn ->
          ReqLLM.generate_text("anthropic:claude-3-haiku", "Hello", max_tokens: 5)
        end
      end
  """
  def use_fixture(provider, fixture_name, test_func) do
    if live_mode?() do
      # Run live and save fixture
      result = test_func.()
      save_fixture(provider, fixture_name, result)
      result
    else
      # Load from fixture
      load_fixture(provider, fixture_name)
    end
  end

  @doc """
  Check if we're in live testing mode.
  """
  def live_mode?() do
    System.get_env("LIVE") in ["1", "true", "TRUE"]
  end

  defp save_fixture(provider, name, result) do
    fixtures_dir = Path.join(@fixtures_base_dir, to_string(provider))
    File.mkdir_p!(fixtures_dir)

    fixture_path = Path.join(fixtures_dir, "#{name}.json")

    fixture_data = %{
      captured_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      provider: provider,
      result: serialize_result(result)
    }

    File.write!(fixture_path, Jason.encode!(fixture_data, pretty: true))
    Logger.debug("Saved fixture: #{provider}/#{name}")
  end

  defp load_fixture(provider, name) do
    fixture_path = Path.join([@fixtures_base_dir, to_string(provider), "#{name}.json"])

    unless File.exists?(fixture_path) do
      raise "Fixture not found: #{fixture_path}. Run with LIVE=true to capture it."
    end

    fixture_path
    |> File.read!()
    |> Jason.decode!()
    |> get_in(["result"])
    |> deserialize_result()
  end

  # Serialize Req.Response and other structs for JSON storage
  defp serialize_result({:ok, %Req.Response{} = resp}) do
    %{
      "type" => "ok_response",
      "status" => resp.status,
      "body" => resp.body,
      "headers" => Map.new(resp.headers)
    }
  end

  defp serialize_result({:error, error}) do
    %{
      "type" => "error",
      "error" => inspect(error)
    }
  end

  defp serialize_result(other) do
    %{
      "type" => "other",
      "data" => other
    }
  end

  # Deserialize back to proper structs
  defp deserialize_result(%{
         "type" => "ok_response",
         "status" => status,
         "body" => body,
         "headers" => headers
       }) do
    {:ok,
     %Req.Response{
       status: status,
       body: body,
       headers: headers,
       trailers: %{},
       private: %{}
     }}
  end

  defp deserialize_result(%{"type" => "error", "error" => error_str}) do
    {:error, error_str}
  end

  defp deserialize_result(%{"type" => "other", "data" => data}) do
    data
  end
end
