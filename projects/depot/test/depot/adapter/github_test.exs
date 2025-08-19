defmodule Depot.Adapter.GitHubTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Depot.Adapter.GitHub
  alias Depot.Stat.{File, Dir}

  @moduletag :github

  setup :copy_modules

  defp copy_modules(_context) do
    Mimic.copy(Tentacat.Contents)
    :ok
  end

  describe "configure/1" do
    test "creates config with required options" do
      {module, config} =
        GitHub.configure(
          owner: "octocat",
          repo: "Hello-World"
        )

      assert module == GitHub

      assert %GitHub{
               owner: "octocat",
               repo: "Hello-World",
               ref: "main",
               client: %Tentacat.Client{auth: nil}
             } = config
    end

    test "creates config with auth token" do
      {module, config} =
        GitHub.configure(
          owner: "octocat",
          repo: "Hello-World",
          ref: "develop",
          auth: %{access_token: "test_token"}
        )

      assert module == GitHub

      assert %GitHub{
               owner: "octocat",
               repo: "Hello-World",
               ref: "develop",
               client: %Tentacat.Client{auth: %{access_token: "test_token"}}
             } = config
    end

    test "creates config with custom commit info" do
      commit_info = %{
        message: "Custom commit",
        committer: %{name: "Test User", email: "test@example.com"},
        author: %{name: "Test Author", email: "author@example.com"}
      }

      {_module, config} =
        GitHub.configure(
          owner: "octocat",
          repo: "Hello-World",
          commit_info: commit_info
        )

      assert config.commit_info == commit_info
    end
  end

  describe "read/2" do
    setup do
      {_module, config} = GitHub.configure(owner: "octocat", repo: "Hello-World")
      {:ok, config: config}
    end

    test "reads file content successfully", %{config: config} do
      content = "Hello, World!"
      encoded_content = Base.encode64(content)

      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "README.md",
                                             "main" ->
        {200, %{"content" => encoded_content, "encoding" => "base64"}, %{}}
      end)

      assert {:ok, ^content} = GitHub.read(config, "README.md")
    end

    test "returns error for missing file", %{config: config} do
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "missing.txt",
                                             "main" ->
        {404, %{"message" => "Not Found"}, %{}}
      end)

      assert {:error, :enoent} = GitHub.read(config, "missing.txt")
    end

    test "returns error for API errors", %{config: config} do
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "error.txt",
                                             "main" ->
        {500, %{"message" => "Server Error"}, %{}}
      end)

      assert {:error, "GitHub API error: 500 - " <> _} = GitHub.read(config, "error.txt")
    end

    test "handles malformed base64 content", %{config: config} do
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "malformed.txt",
                                             "main" ->
        {200, %{"content" => "invalid-base64!", "encoding" => "base64"}, %{}}
      end)

      assert_raise ArgumentError, fn ->
        GitHub.read(config, "malformed.txt")
      end
    end
  end

  describe "write/3" do
    setup do
      {_module, config} =
        GitHub.configure(
          owner: "octocat",
          repo: "Hello-World",
          commit_info: %{
            message: "Test commit",
            committer: %{name: "Test", email: "test@example.com"},
            author: %{name: "Test", email: "test@example.com"}
          }
        )

      {:ok, config: config}
    end

    test "creates new file", %{config: config} do
      content = "New file content"

      # File doesn't exist
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "new.txt",
                                             "main" ->
        {404, %{"message" => "Not Found"}, %{}}
      end)

      # Create file
      expect(Tentacat.Contents, :create, fn _client,
                                            "octocat",
                                            "Hello-World",
                                            "new.txt",
                                            params ->
        assert params.message == "Test commit"
        assert params.content == Base.encode64(content)
        assert params.committer.name == "Test"
        refute Map.has_key?(params, :sha)

        {201, %{"commit" => %{"sha" => "abc123"}}, %{}}
      end)

      assert :ok = GitHub.write(config, "new.txt", content, [])
    end

    test "updates existing file", %{config: config} do
      content = "Updated content"
      existing_sha = "existing_sha_123"

      # File exists
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "existing.txt",
                                             "main" ->
        {200, %{"sha" => existing_sha}, %{}}
      end)

      # Update file
      expect(Tentacat.Contents, :create, fn _client,
                                            "octocat",
                                            "Hello-World",
                                            "existing.txt",
                                            params ->
        assert params.sha == existing_sha
        assert params.content == Base.encode64(content)

        {200, %{"commit" => %{"sha" => "def456"}}, %{}}
      end)

      assert :ok = GitHub.write(config, "existing.txt", content, [])
    end

    test "uses custom commit options", %{config: config} do
      content = "Content with custom commit"

      expect(Tentacat.Contents, :find_in, fn _, _, _, _, _ ->
        {404, %{}, %{}}
      end)

      expect(Tentacat.Contents, :create, fn _client,
                                            "octocat",
                                            "Hello-World",
                                            "custom.txt",
                                            params ->
        assert params.message == "Custom message"
        assert params.committer == %{name: "Custom", email: "custom@example.com"}

        {201, %{}, %{}}
      end)

      opts = [
        message: "Custom message",
        committer: %{name: "Custom", email: "custom@example.com"}
      ]

      assert :ok = GitHub.write(config, "custom.txt", content, opts)
    end

    test "returns error for write API failures", %{config: config} do
      content = "Content that will fail"

      expect(Tentacat.Contents, :find_in, fn _, _, _, _, _ ->
        {404, %{}, %{}}
      end)

      expect(Tentacat.Contents, :create, fn _client,
                                            "octocat",
                                            "Hello-World",
                                            "fail.txt",
                                            _params ->
        {422, %{"message" => "Validation Failed"}, %{}}
      end)

      assert {:error, "GitHub API error: 422 - " <> _} =
               GitHub.write(config, "fail.txt", content, [])
    end

    test "handles file lookup errors gracefully by treating as new file", %{config: config} do
      content = "Content for file with lookup issues"

      # File lookup fails (treated as file doesn't exist)
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "lookup_error.txt",
                                             "main" ->
        {500, %{"message" => "Server Error"}, %{}}
      end)

      # Create file (since lookup failed, sha is nil)
      expect(Tentacat.Contents, :create, fn _client,
                                            "octocat",
                                            "Hello-World",
                                            "lookup_error.txt",
                                            params ->
        # No sha means new file
        refute Map.has_key?(params, :sha)
        {201, %{"commit" => %{"sha" => "abc123"}}, %{}}
      end)

      assert :ok = GitHub.write(config, "lookup_error.txt", content, [])
    end
  end

  describe "delete/2" do
    setup do
      {_module, config} = GitHub.configure(owner: "octocat", repo: "Hello-World")
      {:ok, config: config}
    end

    test "deletes existing file", %{config: config} do
      file_sha = "file_sha_123"

      # File exists
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "delete_me.txt",
                                             "main" ->
        {200, %{"sha" => file_sha}, %{}}
      end)

      # Delete file
      expect(Tentacat.Contents, :remove, fn _client,
                                            "octocat",
                                            "Hello-World",
                                            "delete_me.txt",
                                            params ->
        assert params.sha == file_sha
        assert params.message == "Delete delete_me.txt via Depot"

        {200, %{"commit" => %{"sha" => "ghi789"}}, %{}}
      end)

      assert :ok = GitHub.delete(config, "delete_me.txt")
    end

    test "returns error for missing file", %{config: config} do
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "missing.txt",
                                             "main" ->
        {404, %{"message" => "Not Found"}, %{}}
      end)

      assert {:error, :enoent} = GitHub.delete(config, "missing.txt")
    end

    test "returns error for delete API failures", %{config: config} do
      file_sha = "file_sha_123"

      # File exists
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "error_delete.txt",
                                             "main" ->
        {200, %{"sha" => file_sha}, %{}}
      end)

      # Delete fails
      expect(Tentacat.Contents, :remove, fn _client,
                                            "octocat",
                                            "Hello-World",
                                            "error_delete.txt",
                                            _params ->
        {422, %{"message" => "Validation Failed"}, %{}}
      end)

      assert {:error, "GitHub API error: 422 - " <> _} = GitHub.delete(config, "error_delete.txt")
    end

    test "returns error when file lookup for delete fails", %{config: config} do
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "lookup_error.txt",
                                             "main" ->
        {500, %{"message" => "Server Error"}, %{}}
      end)

      assert {:error, "GitHub API error: 500 - " <> _} = GitHub.delete(config, "lookup_error.txt")
    end
  end

  describe "list_contents/2" do
    setup do
      {_module, config} = GitHub.configure(owner: "octocat", repo: "Hello-World")
      {:ok, config: config}
    end

    test "lists directory contents", %{config: config} do
      contents = [
        %{"type" => "file", "name" => "README.md", "size" => 1024},
        %{"type" => "dir", "name" => "src"},
        %{"type" => "file", "name" => "package.json", "size" => 512}
      ]

      expect(Tentacat.Contents, :find_in, fn _client, "octocat", "Hello-World", "", "main" ->
        {200, contents, %{}}
      end)

      assert {:ok, stats} = GitHub.list_contents(config, "")

      assert length(stats) == 3

      assert %File{name: "README.md", size: 1024} = Enum.find(stats, &(&1.name == "README.md"))
      assert %Dir{name: "src"} = Enum.find(stats, &(&1.name == "src"))

      assert %File{name: "package.json", size: 512} =
               Enum.find(stats, &(&1.name == "package.json"))
    end

    test "handles single file response", %{config: config} do
      file_content = %{"type" => "file", "name" => "single.txt", "size" => 256}

      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "single.txt",
                                             "main" ->
        {200, file_content, %{}}
      end)

      assert {:ok, [%File{name: "single.txt", size: 256}]} =
               GitHub.list_contents(config, "single.txt")
    end

    test "normalizes path for subdirectories", %{config: config} do
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "src/lib",
                                             "main" ->
        {200, [], %{}}
      end)

      assert {:ok, []} = GitHub.list_contents(config, "/src/lib")
    end

    test "returns error for missing directory", %{config: config} do
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "missing",
                                             "main" ->
        {404, %{"message" => "Not Found"}, %{}}
      end)

      assert {:error, :enoent} = GitHub.list_contents(config, "missing")
    end

    test "returns error for API failures", %{config: config} do
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "error_dir",
                                             "main" ->
        {500, %{"message" => "Server Error"}, %{}}
      end)

      assert {:error, "GitHub API error: 500 - " <> _} = GitHub.list_contents(config, "error_dir")
    end
  end

  describe "file_exists?/2" do
    setup do
      {_module, config} = GitHub.configure(owner: "octocat", repo: "Hello-World")
      {:ok, config: config}
    end

    test "returns true for existing file", %{config: config} do
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "exists.txt",
                                             "main" ->
        {200, %{"type" => "file"}, %{}}
      end)

      assert {:ok, :exists} = GitHub.file_exists(config, "exists.txt")
    end

    test "returns false for directory", %{config: config} do
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "directory",
                                             "main" ->
        {200, %{"type" => "dir"}, %{}}
      end)

      assert {:ok, :missing} = GitHub.file_exists(config, "directory")
    end

    test "returns false for missing file", %{config: config} do
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "missing.txt",
                                             "main" ->
        {404, %{}, %{}}
      end)

      assert {:ok, :missing} = GitHub.file_exists(config, "missing.txt")
    end

    test "returns error for API failures", %{config: config} do
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "error.txt",
                                             "main" ->
        {500, %{"message" => "Server Error"}, %{}}
      end)

      assert {:error, "GitHub API error: 500 - " <> _} = GitHub.file_exists(config, "error.txt")
    end
  end

  describe "copy/3" do
    setup do
      {_module, config} = GitHub.configure(owner: "octocat", repo: "Hello-World")
      {:ok, config: config}
    end

    test "copies file by reading and writing", %{config: config} do
      content = "File to copy"

      # Read source
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "source.txt",
                                             "main" ->
        {200, %{"content" => Base.encode64(content), "encoding" => "base64"}, %{}}
      end)

      # Check if destination exists (doesn't)
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "dest.txt",
                                             "main" ->
        {404, %{}, %{}}
      end)

      # Write destination
      expect(Tentacat.Contents, :create, fn _client,
                                            "octocat",
                                            "Hello-World",
                                            "dest.txt",
                                            _params ->
        {201, %{}, %{}}
      end)

      assert :ok = GitHub.copy(config, "source.txt", "dest.txt", [])
    end
  end

  describe "move/3" do
    setup do
      {_module, config} = GitHub.configure(owner: "octocat", repo: "Hello-World")
      {:ok, config: config}
    end

    test "moves file by copying and deleting", %{config: config} do
      content = "File to move"
      source_sha = "source_sha_123"

      # Read source
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "source.txt",
                                             "main" ->
        {200, %{"content" => Base.encode64(content), "encoding" => "base64"}, %{}}
      end)

      # Check if destination exists (doesn't)
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "dest.txt",
                                             "main" ->
        {404, %{}, %{}}
      end)

      # Write destination
      expect(Tentacat.Contents, :create, fn _client,
                                            "octocat",
                                            "Hello-World",
                                            "dest.txt",
                                            _params ->
        {201, %{}, %{}}
      end)

      # Get source for deletion
      expect(Tentacat.Contents, :find_in, fn _client,
                                             "octocat",
                                             "Hello-World",
                                             "source.txt",
                                             "main" ->
        {200, %{"sha" => source_sha}, %{}}
      end)

      # Delete source
      expect(Tentacat.Contents, :remove, fn _client,
                                            "octocat",
                                            "Hello-World",
                                            "source.txt",
                                            _params ->
        {200, %{}, %{}}
      end)

      assert :ok = GitHub.move(config, "source.txt", "dest.txt", [])
    end
  end

  describe "unsupported operations" do
    setup do
      {_module, config} = GitHub.configure(owner: "octocat", repo: "Hello-World")
      {:ok, config: config}
    end

    test "create_directory returns error", %{config: config} do
      assert {:error, "GitHub does not support empty directories"} =
               GitHub.create_directory(config, "new_dir", [])
    end

    test "delete_directory returns error", %{config: config} do
      assert {:error, "GitHub does not support directory deletion via API"} =
               GitHub.delete_directory(config, "some_dir", [])
    end
  end
end
