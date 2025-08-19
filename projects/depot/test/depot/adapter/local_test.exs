defmodule Depot.Adapter.LocalTest do
  use ExUnit.Case, async: true
  import Bitwise
  import Depot.AdapterTest
  doctest Depot.Adapter.Local

  @moduletag :tmp_dir

  def match_mode(input, match) do
    (input &&& 0o777) == match
  end

  adapter_test %{tmp_dir: prefix} do
    filesystem = Depot.Adapter.Local.configure(prefix: prefix)
    {:ok, filesystem: filesystem}
  end

  describe "write" do
    test "success", %{tmp_dir: prefix} do
      {_, config} = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = Depot.Adapter.Local.write(config, "test.txt", "Hello World", [])

      assert {:ok, "Hello World"} = File.read(Path.join(prefix, "test.txt"))
    end

    test "folders are automatically created is missing", %{tmp_dir: prefix} do
      {_, config} = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = Depot.Adapter.Local.write(config, "folder/test.txt", "Hello World", [])

      assert {:ok, "Hello World"} = File.read(Path.join(prefix, "folder/test.txt"))
    end

    test "stream options", %{tmp_dir: prefix} do
      {_, config} = Depot.Adapter.Local.configure(prefix: prefix)

      assert {:ok, %File.Stream{line_or_bytes: :line, modes: [:raw, :read_ahead, :binary]}} =
               Depot.Adapter.Local.write_stream(config, "test.txt", [])

      assert {:ok, %File.Stream{line_or_bytes: 1_024, modes: [:raw, :read_ahead, :binary]}} =
               Depot.Adapter.Local.write_stream(config, "test.txt", chunk_size: 1_024)

      assert {:ok, %File.Stream{modes: [{:encoding, :utf8}, :binary]}} =
               Depot.Adapter.Local.write_stream(config, "test.txt", modes: [encoding: :utf8])
    end

    test "stream success", %{tmp_dir: prefix} do
      {_, config} = Depot.Adapter.Local.configure(prefix: prefix)

      assert {:ok, %File.Stream{} = stream} =
               Depot.Adapter.Local.write_stream(config, "test.txt", [])

      Enum.into(["Hello", " ", "World"], stream)

      assert {:ok, "Hello World"} = File.read(Path.join(prefix, "test.txt"))
    end

    test "default visibility", %{tmp_dir: prefix} do
      {_, config} = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = Depot.Adapter.Local.write(config, "public.txt", "Hello World", visibility: :public)
      :ok = Depot.Adapter.Local.write(config, "private.txt", "Hello World", visibility: :private)

      assert %{mode: mode} = Path.join(prefix, "public.txt") |> File.stat!()
      assert match_mode(mode, 0o644)

      assert %{mode: mode} = Path.join(prefix, "private.txt") |> File.stat!()
      assert match_mode(mode, 0o600)
    end

    test "folder visibility", %{tmp_dir: prefix} do
      {_, config} = Depot.Adapter.Local.configure(prefix: prefix)

      :ok =
        Depot.Adapter.Local.write(config, "public/file.txt", "Hello World", visibility: :public)

      :ok =
        Depot.Adapter.Local.write(config, "private/file.txt", "Hello World",
          directory_visibility: :private
        )

      assert %{mode: mode} = prefix |> File.stat!()
      assert match_mode(mode, 0o755)

      assert %{mode: mode} = Path.join(prefix, "public/") |> File.stat!()
      assert match_mode(mode, 0o755)

      assert %{mode: mode} = Path.join(prefix, "private/") |> File.stat!()
      assert match_mode(mode, 0o700)
    end
  end

  describe "read" do
    test "success", %{tmp_dir: prefix} do
      {_, config} = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = File.write(Path.join(prefix, "test.txt"), "Hello World")

      assert {:ok, "Hello World"} = Depot.Adapter.Local.read(config, "test.txt")
    end

    test "stream options", %{tmp_dir: prefix} do
      {_, config} = Depot.Adapter.Local.configure(prefix: prefix)

      assert {:ok, %File.Stream{line_or_bytes: :line, modes: [:raw, :read_ahead, :binary]}} =
               Depot.Adapter.Local.read_stream(config, "test.txt", [])

      assert {:ok, %File.Stream{line_or_bytes: 1_024, modes: [:raw, :read_ahead, :binary]}} =
               Depot.Adapter.Local.read_stream(config, "test.txt", chunk_size: 1_024)

      assert {:ok, %File.Stream{modes: [{:encoding, :utf8}, :binary]}} =
               Depot.Adapter.Local.read_stream(config, "test.txt", modes: [encoding: :utf8])
    end

    test "stream success", %{tmp_dir: prefix} do
      {_, config} = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = File.write(Path.join(prefix, "test.txt"), "Hello World")

      assert {:ok, %File.Stream{} = stream} =
               Depot.Adapter.Local.read_stream(config, "test.txt", [])

      assert Enum.into(stream, <<>>) == "Hello World"
    end
  end

  describe "delete" do
    test "success", %{tmp_dir: prefix} do
      {_, config} = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = File.write(Path.join(prefix, "test.txt"), "Hello World")

      assert :ok = Depot.Adapter.Local.delete(config, "test.txt")

      assert {:error, :enoent} = File.read(Path.join(prefix, "folder/test.txt"))
    end

    test "successful even if no file to delete", %{tmp_dir: prefix} do
      {_, config} = Depot.Adapter.Local.configure(prefix: prefix)

      assert :ok = Depot.Adapter.Local.delete(config, "test.txt")

      assert {:error, :enoent} = File.read(Path.join(prefix, "folder/test.txt"))
    end
  end
end
