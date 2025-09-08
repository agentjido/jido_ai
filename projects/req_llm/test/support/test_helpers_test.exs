defmodule ReqLLM.TestHelpersTest do
  use ExUnit.Case, async: true
  import ReqLLM.TestHelpers

  describe "fixture infrastructure" do
    test "loads completion fixture" do
      fixture_data = load_fixture_data("anthropic/completion_success")

      assert %{
               "id" => "msg_01XFDUDYJgAACzvnptvVoYEL",
               "content" => [%{"text" => "Hello! How can I help you today?"}]
             } = fixture_data
    end

    test "loads streaming fixture" do
      fixture_data = load_fixture_data("anthropic/completion_streaming")

      assert is_list(fixture_data)
      assert length(fixture_data) > 0

      # Check for message_start event
      assert Enum.any?(fixture_data, fn event -> event["type"] == "message_start" end)
    end

    test "loads error fixture" do
      fixture_data = load_fixture_data("anthropic/error_429")

      assert %{
               "type" => "error",
               "error" => %{"type" => "rate_limit_error"}
             } = fixture_data
    end

    test "creates fixture stub for non-streaming response" do
      stub = fixture_stub("anthropic/completion_success")

      # Simulate conn (minimal structure)
      mock_conn = %{status: nil, resp_body: nil, headers: []}
      result = stub.(mock_conn)

      assert %Req.Response{status: 200} = result
      assert %{"content" => [%{"text" => "Hello! How can I help you today?"}]} = result.body
    end

    test "creates fixture stub for streaming response" do
      stub = fixture_stub("anthropic/completion_streaming")

      mock_conn = %{status: nil, resp_body: nil, headers: []}
      result = stub.(mock_conn)

      assert %Req.Response{status: 200} = result
      assert is_binary(result.body)
      assert result.body =~ "data: "
    end

    test "collect_chunks function works" do
      stream = [1, 2, 3, 4, 5]
      chunks = collect_chunks(stream)
      assert chunks == [1, 2, 3, 4, 5]
    end
  end

  # Helper for tests
  defp load_fixture_data(fixture_path) do
    file_path = Path.join([__DIR__, "fixtures", fixture_path <> ".json"])
    File.read!(file_path) |> Jason.decode!()
  end
end
