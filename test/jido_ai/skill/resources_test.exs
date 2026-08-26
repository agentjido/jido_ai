defmodule Jido.AI.Skill.ResourcesTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skill.{ResourcePolicy, Resources}

  @moduletag :tmp_dir

  describe "list_resources/1" do
    test "returns empty listing for empty directory", %{tmp_dir: tmp_dir} do
      listing = Resources.list_resources(tmp_dir)

      assert listing.scripts == []
      assert listing.references == []
      assert listing.assets == []
      assert listing.resources == []
      assert listing.complete
      refute listing.truncated
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

  describe "list_all/2" do
    test "lists root files, custom directories, and conventional groups with relative paths", %{
      tmp_dir: tmp_dir
    } do
      File.write!(Path.join(tmp_dir, "SKILL.md"), "skill instructions")
      File.write!(Path.join(tmp_dir, "LICENSE"), "MIT")
      File.mkdir_p!(Path.join(tmp_dir, "custom/nested"))
      File.mkdir_p!(Path.join(tmp_dir, "scripts"))
      File.write!(Path.join(tmp_dir, "custom/nested/checks.txt"), "checks")
      File.write!(Path.join(tmp_dir, "scripts/run.sh"), "run")

      assert {:ok, listing} = Resources.list_all(tmp_dir)

      assert Enum.map(listing.resources, & &1.relative_path) == [
               "LICENSE",
               "custom/nested/checks.txt",
               "scripts/run.sh"
             ]

      refute Enum.any?(listing.resources, &Map.has_key?(&1, :absolute_path))
      assert Enum.map(listing.scripts, & &1.relative_path) == ["scripts/run.sh"]
      assert listing.complete
      refute listing.truncated
    end

    test "marks a count-limited result as incomplete", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "a.txt"), "a")
      File.write!(Path.join(tmp_dir, "b.txt"), "b")

      assert {:ok, listing} = Resources.list_all(tmp_dir, max_resources: 1)
      assert Enum.map(listing.resources, & &1.relative_path) == ["a.txt"]
      refute listing.complete
      assert listing.truncated
      assert :max_resources in listing.truncation_reasons
    end

    test "marks skipped deep directories as incomplete", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "root.txt"), "root")
      File.mkdir_p!(Path.join(tmp_dir, "nested"))
      File.write!(Path.join(tmp_dir, "nested/deep.txt"), "deep")

      assert {:ok, listing} = Resources.list_all(tmp_dir, max_depth: 0)
      assert Enum.map(listing.resources, & &1.relative_path) == ["root.txt"]
      assert :max_depth in listing.truncation_reasons
    end

    test "bounds visited directories", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "nested"))
      File.write!(Path.join(tmp_dir, "nested/file.txt"), "file")

      assert {:ok, listing} = Resources.list_all(tmp_dir, max_directories: 1)
      refute listing.complete
      assert :max_directories in listing.truncation_reasons
    end

    test "marks a listing-payload limit as incomplete", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "long-resource-name.txt"), "content")

      assert {:ok, listing} = Resources.list_all(tmp_dir, max_listing_bytes: 2)
      assert listing.resources == []
      assert :max_listing_bytes in listing.truncation_reasons
    end

    test "does not follow resource symlinks", %{tmp_dir: tmp_dir} do
      outside = Path.join(tmp_dir, "outside.txt")
      skill_root = Path.join(tmp_dir, "skill")
      File.mkdir_p!(skill_root)
      File.write!(outside, "outside")
      File.ln_s!(outside, Path.join(skill_root, "linked.txt"))

      assert {:ok, %{resources: []}} = Resources.list_all(skill_root)
    end

    test "validates resource policies", %{tmp_dir: tmp_dir} do
      assert {:error, {:invalid_resource_policy, :max_resources}} =
               Resources.list_all(tmp_dir, max_resources: 0)

      assert {:error, {:invalid_resource_policy, :unknown}} =
               Resources.list_all(tmp_dir, unknown: 1)

      assert {:ok, %ResourcePolicy{max_text_bytes: 12}} =
               ResourcePolicy.new(max_text_bytes: 12)

      assert {:error, {:invalid_resource_policy, :binary}} =
               ResourcePolicy.new(binary: :allow)
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

  describe "load_text/3" do
    test "returns normalized text resource data", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "references"))
      File.write!(Path.join(tmp_dir, "references/guide.md"), "Guide")

      assert {:ok, result} = Resources.load_text(tmp_dir, "references/../references/guide.md")
      assert result == %{content: "Guide", relative_path: "references/guide.md", size: 5}
    end

    test "rejects the skill document and traversal", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "SKILL.md"), "instructions")

      assert {:error, :invalid_resource_path} = Resources.load_text(tmp_dir, "SKILL.md")
      assert {:error, :path_traversal} = Resources.load_text(tmp_dir, "../outside.txt")
      assert {:error, :path_traversal} = Resources.load_text(tmp_dir, "/etc/passwd")
    end

    test "returns not found for a missing file", %{tmp_dir: tmp_dir} do
      assert {:error, :not_found} = Resources.load_text(tmp_dir, "missing.txt")
    end

    test "enforces file and returned-text limits", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "large.txt"), "123456")

      assert {:error, {:resource_too_large, :file, 6, 5}} =
               Resources.load_text(tmp_dir, "large.txt", max_file_bytes: 5)

      assert {:error, {:resource_too_large, :text, 6, 4}} =
               Resources.load_text(tmp_dir, "large.txt", max_file_bytes: 10, max_text_bytes: 4)
    end

    test "rejects binary content", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "image.bin"), <<0xFF, 0xFE, 0x00>>)
      assert {:error, :binary_resource} = Resources.load_text(tmp_dir, "image.bin")
    end

    test "rejects symlinks even when the target stays inside the skill", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "target.txt"), "target")
      File.ln_s!(Path.join(tmp_dir, "target.txt"), Path.join(tmp_dir, "linked.txt"))

      assert {:error, :path_traversal} = Resources.load_text(tmp_dir, "linked.txt")
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
