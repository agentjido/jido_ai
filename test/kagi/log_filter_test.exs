defmodule Kagi.LogFilterTest do
  @moduledoc """
  Tests for the Kagi.LogFilter module.
  """

  use ExUnit.Case

  alias Kagi.LogFilter

  setup do
    original_config = Application.get_env(:kagi, Kagi.LogFilter, [])
    Application.put_env(:kagi, Kagi.LogFilter, enabled: true, redaction_text: "[REDACTED]")

    on_exit(fn ->
      if original_config == [] do
        Application.delete_env(:kagi, Kagi.LogFilter)
      else
        Application.put_env(:kagi, Kagi.LogFilter, original_config)
      end
    end)

    :ok
  end

  describe "filter/1" do
    test "redacts secrets from log messages when enabled" do
      event = {:info, self(), {Logger, "API_KEY=sk-1234567890abcdef", %{}, []}}
      {level, _pid, {Logger, filtered_message, _metadata, _opts}} = LogFilter.filter(event)

      assert level == :info
      assert filtered_message == "API_KEY=[REDACTED]"
    end

    test "passes through messages when disabled" do
      Application.put_env(:kagi, Kagi.LogFilter, enabled: false)

      original_message = "API_KEY=sk-1234567890abcdef"
      event = {:info, self(), {Logger, original_message, %{}, []}}
      result = LogFilter.filter(event)

      assert result == event
    end
  end

  describe "redact_secrets/1" do
    test "redacts various secret patterns" do
      message = "API_KEY=sk-1234567890 PASSWORD=secret123 TOKEN=bearer_abc"
      result = LogFilter.redact_secrets(message)

      assert result == "API_KEY=[REDACTED] PASSWORD=[REDACTED] TOKEN=[REDACTED]"
    end

    test "handles URL with secrets" do
      message = "Connecting to https://user:secret@api.example.com"
      result = LogFilter.redact_secrets(message)

      assert String.contains?(result, "[REDACTED]")
    end
  end

  describe "sensitive_key?/1" do
    test "identifies sensitive keys" do
      assert LogFilter.sensitive_key?(:password) == true
      assert LogFilter.sensitive_key?("api_key") == true
      assert LogFilter.sensitive_key?(:secret) == true
      assert LogFilter.sensitive_key?("normal_key") == false
    end
  end

  describe "configuration" do
    test "uses custom redaction text" do
      Application.put_env(:kagi, Kagi.LogFilter, redaction_text: "***HIDDEN***")

      message = "API_KEY=sk-1234567890"
      result = LogFilter.redact_secrets(message)

      assert result == "API_KEY=***HIDDEN***"
    end
  end
end
