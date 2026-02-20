defmodule Mix.Tasks.JidoAi.SkillTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.JidoAi.Skill, as: SkillTask

  setup do
    Mix.shell(Mix.Shell.Process)

    tmp_dir = Path.join(System.tmp_dir!(), "jido_ai_skill_task_#{System.unique_integer([:positive, :monotonic])}")
    valid_dir = Path.join(tmp_dir, "valid")
    invalid_dir = Path.join(tmp_dir, "invalid")

    File.mkdir_p!(valid_dir)
    File.mkdir_p!(invalid_dir)

    valid_skill_path = Path.join(valid_dir, "SKILL.md")
    invalid_skill_path = Path.join(invalid_dir, "SKILL.md")

    File.write!(
      valid_skill_path,
      """
      ---
      name: demo-skill
      description: Demo skill for task tests.
      license: Apache-2.0
      allowed-tools: read_file grep
      ---

      # Demo Skill

      This is a demo skill body.
      """
    )

    File.write!(invalid_skill_path, "# Invalid skill content without frontmatter")

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
      File.rm_rf!(tmp_dir)
    end)

    {:ok,
     tmp_dir: tmp_dir, valid_dir: valid_dir, valid_skill_path: valid_skill_path, invalid_skill_path: invalid_skill_path}
  end

  describe "list command" do
    test "lists valid skills and reports invalid files", %{tmp_dir: tmp_dir} do
      messages = run_task_with_output(["list", tmp_dir])
      output = format_messages(messages)

      assert output =~ "Skills found: 1"
      assert output =~ "demo-skill"
      assert output =~ "Demo skill for task tests."
      assert output =~ "Errors: 1"
      assert output =~ "No YAML frontmatter found"
    end

    test "outputs JSON with skill summary", %{valid_dir: valid_dir} do
      messages = run_task_with_output(["list", valid_dir, "--json"])
      json = first_info(messages)

      assert {:ok, [decoded]} = Jason.decode(json)
      assert decoded["name"] == "demo-skill"
      assert decoded["description"] == "Demo skill for task tests."
      assert decoded["license"] == "Apache-2.0"
      assert decoded["allowed_tools"] == ["read_file", "grep"]
    end

    test "prints usage when no path is provided" do
      messages = run_task_with_output(["list"])
      errors = all_errors(messages)

      assert Enum.any?(errors, &String.contains?(&1, "Usage: mix jido_ai.skill list <path> [<path>...]"))
    end
  end

  describe "show command" do
    test "prints human-readable details and body", %{valid_skill_path: path} do
      messages = run_task_with_output(["show", path, "--body"])
      output = format_messages(messages)

      assert output =~ "demo-skill"
      assert output =~ "Description:"
      assert output =~ "Allowed Tools:"
      assert output =~ "read_file, grep"
      assert output =~ "Body:"
      assert output =~ "# Demo Skill"
    end

    test "prints JSON details when requested", %{valid_skill_path: path} do
      messages = run_task_with_output(["show", path, "--json", "--body"])
      json = first_info(messages)

      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["name"] == "demo-skill"
      assert decoded["description"] == "Demo skill for task tests."
      assert decoded["allowed_tools"] == ["read_file", "grep"]
      assert decoded["body"] =~ "# Demo Skill"
    end

    test "prints formatted loader error for invalid skill", %{invalid_skill_path: path} do
      messages = run_task_with_output(["show", path])
      errors = all_errors(messages)

      assert Enum.any?(errors, &String.contains?(&1, "Failed to load skill: No YAML frontmatter found"))
    end
  end

  describe "validate command" do
    test "outputs JSON summary for valid and invalid files", %{valid_skill_path: valid, invalid_skill_path: invalid} do
      messages = run_task_with_output(["validate", valid, invalid, "--json"])
      json = first_info(messages)

      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["valid"] == 1
      assert decoded["errors"] == 1
      assert Enum.any?(decoded["results"], &(&1["path"] == valid and &1["valid"] == true))
      assert Enum.any?(decoded["results"], &(&1["path"] == invalid and &1["valid"] == false))
    end

    test "raises in strict mode when validation errors are present", %{invalid_skill_path: invalid} do
      flush_shell_messages()

      assert_raise Mix.Error, "Validation failed with 1 error(s)", fn ->
        invoke_task(["validate", invalid, "--strict"])
      end
    end

    test "prints usage when no path is provided" do
      messages = run_task_with_output(["validate"])
      errors = all_errors(messages)

      assert Enum.any?(errors, &String.contains?(&1, "Usage: mix jido_ai.skill validate <path> [<path>...]"))
    end
  end

  describe "unknown command" do
    test "prints help guidance" do
      messages = run_task_with_output(["not-a-command"])
      errors = all_errors(messages)

      assert Enum.any?(errors, &String.contains?(&1, "Unknown command. Run `mix jido_ai.skill` for help."))
    end
  end

  defp run_task_with_output(args) do
    flush_shell_messages()
    invoke_task(args)
    drain_shell_messages()
  end

  defp invoke_task(args) do
    Mix.Task.reenable("jido_ai.skill")
    SkillTask.run(args)
  end

  defp drain_shell_messages(messages \\ []) do
    receive do
      {:mix_shell, level, [message]} ->
        text = IO.chardata_to_string(message)
        drain_shell_messages([{level, text} | messages])
    after
      25 ->
        Enum.reverse(messages)
    end
  end

  defp flush_shell_messages do
    receive do
      {:mix_shell, _, _} -> flush_shell_messages()
    after
      0 -> :ok
    end
  end

  defp format_messages(messages) do
    messages
    |> Enum.map(fn {_level, text} -> text end)
    |> Enum.join("\n")
  end

  defp first_info(messages) do
    messages
    |> Enum.find_value(fn
      {:info, text} -> text
      _ -> nil
    end)
  end

  defp all_errors(messages) do
    for {:error, text} <- messages, do: text
  end
end
