defmodule Jido.AI.Skill.ResourcesTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skill.Resources

  @moduletag :tmp_dir

  describe "list_resources/1" do
    test "returns empty listing for empty directory", %{tmp_dir: tmp_dir} do
      listing = Resources.list_resources(tmp_dir)

      assert listing.scripts == []
      assert listing.references == []
      assert listing.assets == []
    end

    test "discovers files in resource subdirectories", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "scripts"))
      File.mkdir_p!(Path.join(tmp_dir, "references"))
      File.write!(Path.join(tmp_dir, "scripts/setup.sh"), "#!/bin/bash")
      File.write!(Path.join(tmp_dir, "references/guide.md"), "# Guide")

      listing = Resources.list_resources(tmp_dir)

      assert length(listing.scripts) == 1
      assert hd(listing.scripts).name == "setup.sh"
      assert hd(listing.scripts).relative_path == "scripts/setup.sh"

      assert length(listing.references) == 1
      assert hd(listing.references).name == "guide.md"
    end
  end

  describe "load_resource/2" do
    test "loads file content", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test.txt")
      File.write!(path, "hello world")

      assert Resources.load_resource(tmp_dir, "test.txt") == {:ok, "hello world"}
    end

    test "returns error for missing file", %{tmp_dir: tmp_dir} do
      assert Resources.load_resource(tmp_dir, "missing.txt") ==
               {:error, :not_found}
    end
  end

  describe "exists?/2" do
    test "returns true for existing file", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "exists.txt"), "")

      assert Resources.exists?(tmp_dir, "exists.txt")
    end

    test "returns false for missing file", %{tmp_dir: tmp_dir} do
      refute Resources.exists?(tmp_dir, "missing.txt")
    end
  end

  describe "resolve_path/2" do
    test "resolves relative paths" do
      assert Resources.resolve_path("/base", "sub/file.txt") ==
               {:ok, Path.join("/base", "sub/file.txt")}
    end

    test "blocks path traversal attempts" do
      assert Resources.resolve_path("/base", "../../etc/passwd") ==
               {:error, :path_traversal}
    end

    test "blocks absolute path injection" do
      assert Resources.resolve_path("/base", "/etc/passwd") ==
               {:error, :path_traversal}
    end

    test "blocks symlink escapes", %{tmp_dir: tmp_dir} do
      outside_path = Path.join(tmp_dir, "outside.txt")
      skill_root = Path.join(tmp_dir, "skill")
      link_path = Path.join(skill_root, "linked.txt")

      File.mkdir_p!(skill_root)
      File.write!(outside_path, "secret")
      File.ln_s!(outside_path, link_path)

      assert Resources.resolve_path(skill_root, "linked.txt") ==
               {:error, :path_traversal}
    end

    test "blocks symlink escapes even when final target is missing", %{tmp_dir: tmp_dir} do
      outside_dir = Path.join(tmp_dir, "outside")
      skill_root = Path.join(tmp_dir, "skill")
      link_path = Path.join(skill_root, "linked")

      File.mkdir_p!(outside_dir)
      File.mkdir_p!(skill_root)
      File.ln_s!(outside_dir, link_path)

      assert Resources.resolve_path(skill_root, "linked/missing.txt") ==
               {:error, :path_traversal}
    end
  end

  describe "search/2" do
    test "filters symlink escapes from matches", %{tmp_dir: tmp_dir} do
      outside_dir = Path.join(tmp_dir, "outside")
      skill_root = Path.join(tmp_dir, "skill")
      references_dir = Path.join(skill_root, "references")

      File.mkdir_p!(outside_dir)
      File.mkdir_p!(references_dir)
      File.write!(Path.join(references_dir, "inside.md"), "# Inside")
      File.write!(Path.join(outside_dir, "outside.md"), "# Outside")
      File.ln_s!(outside_dir, Path.join(references_dir, "linked"))

      matches = Resources.search(skill_root, "references/**/*.md")

      assert Enum.map(matches, & &1.relative_path) == ["references/inside.md"]
    end
  end
end
