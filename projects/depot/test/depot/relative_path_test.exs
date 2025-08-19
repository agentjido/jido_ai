defmodule Depot.RelativePathTest do
  use ExUnit.Case, async: true
  alias Depot.RelativePath

  describe "relative?/1" do
    test "returns true for relative paths" do
      assert RelativePath.relative?("path/to/dir")
      assert RelativePath.relative?("./path/to/dir")
      assert RelativePath.relative?("../path/to/dir")
    end

    test "returns false for absolute paths" do
      refute RelativePath.relative?("/path/to/dir")
      refute RelativePath.relative?("C:/path/to/dir")
      refute RelativePath.relative?("//path/to/dir")
      refute RelativePath.relative?("C:path/to/dir")
    end
  end

  describe "normalize/1" do
    test "normalizes relative paths" do
      assert {:ok, "path/to/dir"} = RelativePath.normalize("path/to/dir")
      assert {:ok, "path/to/dir/"} = RelativePath.normalize("path/to/dir/")
      assert {:ok, "to/dir"} = RelativePath.normalize("path/../to/dir")
    end

    test "returns error for absolute paths" do
      assert {:error, {:path, :absolute}} = RelativePath.normalize("/path/to/dir")
      assert {:error, {:path, :absolute}} = RelativePath.normalize("C:/path/to/dir")
    end

    test "returns error for traversal attempts" do
      assert {:error, {:path, :traversal}} = RelativePath.normalize("../path/to/dir")
      assert {:error, {:path, :traversal}} = RelativePath.normalize("path/../../to/dir")
    end
  end

  describe "expand/1" do
    test "expands relative paths" do
      assert {:ok, "path/to/dir"} = RelativePath.expand("path/to/dir")
      assert {:ok, "to/dir"} = RelativePath.expand("path/../to/dir")
      assert {:ok, "path/to"} = RelativePath.expand("path/./to")
    end

    test "returns error for traversal attempts" do
      assert {:error, :traversal} = RelativePath.expand("../path/to/dir")
      assert {:error, :traversal} = RelativePath.expand("path/../../path/to/dir")
      assert {:error, :traversal} = RelativePath.expand("path/../path/../../to/dir")
      assert {:error, :traversal} = RelativePath.expand("path/../path/to/../../../")
    end
  end

  describe "expand/1 and expand_dot/1" do
    test "expands path with Windows-style drive letter" do
      assert {:ok, "path/to/dir"} = RelativePath.expand("C:/path/to/dir")
    end

    test "handles empty path" do
      assert {:ok, ""} = RelativePath.expand("")
    end

    test "removes single dot segments" do
      assert {:ok, "path/to/dir"} = RelativePath.expand("./path/./to/./dir")
    end

    test "removes double dot segments correctly" do
      assert {:ok, "path/dir"} = RelativePath.expand("path/to/../dir")
      assert {:ok, "dir"} = RelativePath.expand("path/to/../../dir")
    end

    test "throws :traversal for paths attempting to go above root" do
      assert {:error, :traversal} = RelativePath.expand("path/../../..")
    end

    test "handles paths with only dot segments" do
      assert {:ok, ""} = RelativePath.expand("./././")
    end
  end

  describe "join_prefix/2" do
    test "joins prefix with relative path" do
      assert "/path/to/dir" = RelativePath.join_prefix("/", "path/to/dir")
      assert "/path/to/dir/" = RelativePath.join_prefix("/", "path/to/dir/")
      assert "/prefix/path/to/dir" = RelativePath.join_prefix("/prefix", "path/to/dir")
      assert "/prefix/path/to/dir" = RelativePath.join_prefix("/prefix/", "path/to/dir")
      assert "C:/path/to/dir" = RelativePath.join_prefix("C:/", "path/to/dir")
      assert "C:/prefix/path/to/dir" = RelativePath.join_prefix("C:/prefix", "path/to/dir")
      assert "C:/prefix/path/to/dir" = RelativePath.join_prefix("C:/prefix/", "path/to/dir")
      assert "//prefix/path/to/dir" = RelativePath.join_prefix("//prefix/", "path/to/dir")
    end
  end

  describe "strip_prefix/2" do
    test "strips prefix from path" do
      assert "path/to/dir" = RelativePath.strip_prefix("/", "/path/to/dir")
      assert "path/to/dir" = RelativePath.strip_prefix("/prefix", "/prefix/path/to/dir")
      assert "path/to/dir" = RelativePath.strip_prefix("/prefix/", "/prefix/path/to/dir")
      assert "path/to/dir" = RelativePath.strip_prefix("C:/", "C:/path/to/dir")
      assert "path/to/dir" = RelativePath.strip_prefix("C:/prefix", "C:/prefix/path/to/dir")
      assert "path/to/dir" = RelativePath.strip_prefix("C:/prefix/", "C:/prefix/path/to/dir")
      assert "path/to/dir" = RelativePath.strip_prefix("//prefix/", "//prefix/path/to/dir")
    end
  end

  describe "assert_directory/1" do
    test "returns ok for directory paths" do
      assert {:ok, "path/to/dir/"} = RelativePath.assert_directory("path/to/dir/")
    end

    test "returns error for non-directory paths" do
      assert {:error, :enotdir} = RelativePath.assert_directory("path/to/file")
    end
  end
end
