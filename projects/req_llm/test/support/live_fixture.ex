defmodule ReqLLM.Test.LiveFixture do
  @moduledoc """
  Simple test fixture helper for live API calls vs cached responses.
  
  Set LIVE=true to run against live APIs and cache results.
  Otherwise, use cached fixtures for fast testing.
  """
  
  require Logger

  @doc """
  Run test function live or load from fixture.
  """
  def use_fixture(provider, fixture_name, test_func) do
    if live_mode?() do
      result = test_func.()
      save_fixture(provider, fixture_name, result)
      result
    else
      load_fixture(provider, fixture_name)
    end
  end

  def live_mode?() do
    System.get_env("LIVE") in ["1", "true", "TRUE"]
  end

  # Save result to JSON fixture
  defp save_fixture(provider, name, result) do
    fixture_path = fixture_path(provider, name)
    File.mkdir_p!(Path.dirname(fixture_path))
    
    fixture_data = %{
      captured_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      result: serialize_result(result)
    }
    
    File.write!(fixture_path, Jason.encode!(fixture_data, pretty: true))
    Logger.debug("Saved fixture: #{provider}/#{name}")
  end

  # Handle tuple serialization
  defp serialize_result({:ok, %ReqLLM.Response{} = resp}) do
    %{"type" => "ok_req_llm_response", "data" => resp}
  end

  defp serialize_result({:error, error}) do
    %{"type" => "error", "error" => inspect(error)}
  end

  defp serialize_result(other) do
    %{"type" => "other", "data" => other}
  end

  # Load result from JSON fixture  
  defp load_fixture(provider, name) do
    fixture_path = fixture_path(provider, name)
    
    unless File.exists?(fixture_path) do
      raise "Fixture not found: #{fixture_path}. Run with LIVE=true to capture it."
    end
    
    fixture_path
    |> File.read!()
    |> Jason.decode!()
    |> Map.get("result")
    |> reconstruct_result()
  end

  defp fixture_path(provider, name) do
    Path.join([__DIR__, "fixtures", to_string(provider), "#{name}.json"])
  end

  # Reconstruct structs from JSON data
  defp reconstruct_result(%{"type" => "ok_req_llm_response", "data" => data}) do
    {:ok, rebuild_response(data)}
  end

  defp reconstruct_result(%{"type" => "error", "error" => error}) do
    {:error, error}
  end

  defp reconstruct_result(other) do
    other
  end

  # Simple struct reconstruction for ReqLLM.Response
  defp rebuild_response(data) do
    %ReqLLM.Response{
      id: data["id"],
      model: data["model"], 
      context: rebuild_context(data["context"]),
      message: rebuild_message(data["message"]),
      stream?: data["stream?"] || false,
      stream: data["stream"],
      usage: data["usage"],
      finish_reason: data["finish_reason"] && String.to_atom(data["finish_reason"]),
      provider_meta: data["provider_meta"],
      error: data["error"]
    }
  end

  defp rebuild_context(nil), do: nil
  defp rebuild_context(%{"messages" => messages}) do
    %ReqLLM.Context{messages: Enum.map(messages, &rebuild_message/1)}
  end

  defp rebuild_message(nil), do: nil
  defp rebuild_message(%{"role" => role, "content" => content} = data) do
    %ReqLLM.Message{
      role: String.to_atom(role),
      content: Enum.map(content || [], &rebuild_content_part/1),
      name: data["name"],
      tool_call_id: data["tool_call_id"],
      tool_calls: data["tool_calls"],
      metadata: data["metadata"] || %{}
    }
  end

  defp rebuild_content_part(%{"type" => type} = data) do
    %ReqLLM.Message.ContentPart{
      type: String.to_atom(type),
      text: data["text"],
      url: data["url"], 
      data: data["data"],
      media_type: data["media_type"],
      filename: data["filename"],
      tool_call_id: data["tool_call_id"],
      tool_name: data["tool_name"],
      input: data["input"],
      output: data["output"],
      metadata: data["metadata"] || %{}
    }
  end
end
