defmodule JidoTest.UtilTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias Jido.Util

  @invalid_name_format "Invalid name format."
  @validate_name_error "The name must start with a letter and contain only letters, numbers, and underscores."

  describe "validate_name/1" do
    test "validate_name accepts valid names" do
      assert {:ok, "valid_name"} = Util.validate_name("valid_name")
      assert {:ok, "valid_name_123"} = Util.validate_name("valid_name_123")
      assert {:ok, "VALID_NAME"} = Util.validate_name("VALID_NAME")
    end

    test "validate_name rejects invalid names" do
      assert {:error, @validate_name_error} = Util.validate_name("invalid-name")
      assert {:error, @validate_name_error} = Util.validate_name("invalid name")
      assert {:error, @validate_name_error} = Util.validate_name("123invalid")
      assert {:error, @validate_name_error} = Util.validate_name("")
    end

    test "validate_name rejects non-string inputs" do
      assert {:error, @invalid_name_format} = Util.validate_name(123)
      assert {:error, @invalid_name_format} = Util.validate_name(%{})
      assert {:error, @invalid_name_format} = Util.validate_name(nil)
    end
  end

  describe "cond_log/4" do
    setup do
      Logger.put_process_level(self(), :debug)
      on_exit(fn -> Logger.delete_process_level(self()) end)
    end

    test "logs when message level meets threshold" do
      log =
        capture_log(fn ->
          Util.cond_log(:info, :info, "test message")
          Util.cond_log(:debug, :info, "test message")
        end)

      assert log =~ "test message"

      info_count =
        log
        |> String.split("[info]")
        |> length()
        |> Kernel.-(1)

      assert info_count == 2
    end

    test "does not log when message level below threshold" do
      log =
        capture_log(fn ->
          Util.cond_log(:info, :debug, "test message")
        end)

      refute log =~ "test message"
    end

    test "handles invalid log levels" do
      log =
        capture_log(fn ->
          Util.cond_log(:invalid, :info, "test message")
          Util.cond_log(:info, :invalid, "test message")
        end)

      refute log =~ "test message"
    end

    test "passes through logger options" do
      log =
        capture_log(fn ->
          Util.cond_log(:info, :info, "test message", timestamp: false)
        end)

      assert log =~ "test message"
    end
  end
end
