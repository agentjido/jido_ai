defmodule JidoTest.AI.Prompt.TemplateTest do
  use ExUnit.Case, async: false
  doctest Jido.AI.Prompt.Template
  @moduletag :capture_log

  alias Jido.AI.Prompt.MessageItem
  alias Jido.AI.Prompt.Template

  describe "new/1 and new!/1" do
    test "creates a template with defaults" do
      {:ok, template} = Template.new(%{text: "Hello <%= @name %>"})
      assert template.text == "Hello <%= @name %>"
      assert template.role == :user
      assert template.engine == :eex
      assert template.cacheable == true
      assert template.created_at != nil
      assert is_map(template.performance_stats)
      # No estimation without sample inputs
      assert template.estimated_tokens == nil
      assert template.sample_inputs == %{}

      # Test with sample inputs
      {:ok, template} =
        Template.new(%{
          text: "Hello <%= @name %>",
          sample_inputs: %{name: "World"}
        })

      assert is_integer(template.estimated_tokens)

      template_bang = Template.new!(%{text: "Hello <%= @name %>", role: :system})
      assert template_bang.role == :system
    end

    test "validates template syntax" do
      assert {:error, _} = Template.new(%{text: "<%= if true do %>incomplete"})
      assert {:ok, _} = Template.new(%{text: "<%= if true do %>complete<% end %>"})
    end

    test "returns error for invalid options" do
      assert {:error, _} = Template.new(%{text: 123})

      assert_raise Jido.AI.Error, fn ->
        Template.new!(%{text: nil})
      end
    end
  end

  describe "from_string/2 and from_string!/2" do
    test "builds a user template from a simple string" do
      {:ok, template} = Template.from_string("Hello <%= @name %>")
      assert template.text == "Hello <%= @name %>"
      assert template.role == :user
    end

    test "supports specifying role in opts" do
      {:ok, template} = Template.from_string("Hello <%= @name %>", role: :assistant)
      assert template.role == :assistant
    end

    test "raises on invalid string input" do
      assert_raise Jido.AI.Error, fn ->
        Template.from_string!(nil)
      end
    end
  end

  describe "from_string_with_defaults/3" do
    test "applies defaults to the template" do
      {:ok, template} =
        Template.from_string_with_defaults("Hi <%= @name %>, your city is <%= @city %>", %{
          city: "Paris"
        })

      assert template.inputs == %{city: "Paris"}
    end

    test "raises if invalid" do
      assert_raise Jido.AI.Error, fn ->
        Template.from_string_with_defaults!(nil, %{city: "Paris"})
      end
    end
  end

  describe "format/3" do
    test "substitutes inputs and returns a string" do
      template = Template.new!(%{text: "Hello <%= @name %>, you are <%= @age %> years old."})
      output = Template.format(template, %{name: "Alice", age: 30})
      assert output == "Hello Alice, you are 30 years old."
    end

    test "uses default inputs if not overridden" do
      template =
        Template.new!(%{
          text: "Hello <%= @name %>, welcome to <%= @city %>!",
          inputs: %{name: "Alice", city: "Wonderland"}
        })

      assert Template.format(template) == "Hello Alice, welcome to Wonderland!"
      assert Template.format(template, %{city: "Narnia"}) == "Hello Alice, welcome to Narnia!"
    end

    test "applies pre_hook and post_hook if provided" do
      template = Template.new!(%{text: "Hello <%= @name %>"})
      pre = fn assigns -> Map.update!(assigns, :name, &"#{&1} (transformed)") end
      post = fn rendered -> "[[#{rendered}]]" end

      output = Template.format(template, %{name: "Bob"}, pre_hook: pre, post_hook: post)
      assert output == "[[Hello Bob (transformed)]]"
    end
  end

  describe "format_text/3" do
    test "renders with EEx by default" do
      result = Template.format_text("Hello <%= @thing %>", %{thing: "World"}, :eex)
      assert result == "Hello World"
    end

    test "raises error for unsupported engines" do
      assert_raise Jido.AI.Error,
                   "Invalid prompt template: invalid value for :engine option: expected one of [:eex], got: :heex",
                   fn ->
                     Template.new!(%{text: "Hello <%= @thing %>", engine: :heex})
                   end
    end
  end

  describe "format_composed/3" do
    test "composes multiple templates into one" do
      main_template = Template.new!(%{text: "<%= @part1 %> and <%= @part2 %>"})
      t1 = Template.new!(%{text: "AAA <%= @x %>"})
      t2 = Template.new!(%{text: "BBB <%= @y %>"})

      text =
        Template.format_composed(
          main_template,
          %{part1: t1, part2: t2},
          %{x: "X", y: "Y"}
        )

      assert text == "AAA X and BBB Y"
    end

    test "supports plain text as sub-templates" do
      main_template = Template.new!(%{text: "Header: <%= @intro %>\nBody: <%= @body %>"})

      text =
        Template.format_composed(
          main_template,
          %{intro: "Just text", body: "More text"},
          %{}
        )

      assert text == "Header: Just text\nBody: More text"
    end

    test "raises if sub-template is invalid" do
      main_template = Template.new!(%{text: "<%= @invalid %>"})

      assert_raise Jido.AI.Error, fn ->
        Template.format_composed(main_template, %{invalid: 123}, %{})
      end
    end
  end

  describe "estimate_tokens/2" do
    test "returns approximate token count" do
      template = Template.new!(%{text: "Hello <%= @name %>"})
      tokens = Template.estimate_tokens(template, %{name: "Alice"})
      # Very approximate, but we expect a small integer
      assert tokens > 0
    end
  end

  describe "to_message/2 and to_message!/2" do
    test "converts template to a message" do
      template = Template.new!(%{text: "Hi <%= @name %>!", role: :assistant})
      {:ok, msg} = Template.to_message(template, %{name: "Alice"})
      assert msg.role == :assistant
      assert msg.content == "Hi Alice!"
      assert %MessageItem{} = msg
    end

    # test "to_message!/2 raises if invalid" do
    #   template =
    #     Template.new!(%{
    #       text: "Hi <%= raise \"test error\" %>!",
    #       role: :assistant,
    #       estimated_tokens: 10
    #     })
    #   assert_raise Jido.AI.Error, fn ->
    #     Template.to_message!(template, %{})
    #   end
    # end
  end

  describe "to_messages!/2" do
    test "processes a list of templates, messages, and strings" do
      t1 = Template.new!(%{text: "System: <%= @sysinfo %>", role: :system})
      t2 = Template.new!(%{text: "Question: <%= @question %>", role: :user})

      out =
        Template.to_messages!([t1, t2, "A direct user string"], %{
          sysinfo: "Guide the user",
          question: "What is 2+2?"
        })

      assert length(out) == 3
      [m1, m2, m3] = out
      assert m1.role == :system
      assert m1.content == "System: Guide the user"
      assert m2.role == :user
      assert m2.content == "Question: What is 2+2?"
      assert m3.role == :user
      assert m3.content == "A direct user string"
    end
  end

  describe "compile/1" do
    test "compiles the template successfully" do
      template = Template.new!(%{text: "Compiling <%= @test %>"})
      assert {:ok, _compiled} = Template.compile(template)
    end

    test "returns an error if compilation fails" do
      result = Template.new(%{text: "<%= if true do %>Missing end tag"})
      assert {:error, error} = result
      assert error =~ "expected a closing '<% end %>'"
    end
  end

  describe "sanitize_inputs/1" do
    test "escapes certain characters in string values" do
      sanitized =
        Template.sanitize_inputs(%{
          name: "Alice<evil>",
          code: "<%= @injection %>",
          number: 42
        })

      assert sanitized[:name] == "Alice\\<evil\\>"
      assert sanitized[:code] == "\\<%= @injection %\\>"
      assert sanitized[:number] == 42
    end
  end

  describe "record_usage/2" do
    test "updates performance stats with usage metrics" do
      template = Template.new!(%{text: "Hello <%= @name %>"})

      updated =
        Template.record_usage(template, %{
          tokens_used: 100,
          response_time_ms: 500,
          success: true
        })

      assert updated.performance_stats.usage_count == 1
      assert updated.performance_stats.avg_tokens == 100
      assert updated.performance_stats.avg_response_time == 500
      assert updated.performance_stats.success_count == 1
      assert updated.performance_stats.last_used_at != nil
    end

    test "calculates averages correctly over multiple uses" do
      template = Template.new!(%{text: "Test"})

      template = Template.record_usage(template, %{tokens_used: 100})
      assert template.performance_stats.avg_tokens == 100

      template = Template.record_usage(template, %{tokens_used: 200})
      # (100 + 200) / 2
      assert template.performance_stats.avg_tokens == 150
    end
  end

  describe "increment_version/1" do
    test "increments version number" do
      template = Template.new!(%{text: "Test", version: 1})
      updated = Template.increment_version(template)
      assert updated.version == 2
    end

    test "handles nil version" do
      template = Template.new!(%{text: "Test", version: nil})
      updated = Template.increment_version(template)
      assert updated.version == 2
    end
  end

  describe "versioning" do
    test "new template starts with version 1" do
      template = Template.new!(%{text: "Initial text"})
      assert template.version == 1
      assert template.version_history == []
    end

    test "increment_version adds current version to history" do
      template = Template.new!(%{text: "Initial text"})
      updated = Template.increment_version(template)

      assert updated.version == 2
      assert length(updated.version_history) == 1
      [history_entry] = updated.version_history
      assert history_entry.version == 1
      assert history_entry.text == "Initial text"
    end

    test "update_text increments version and updates text" do
      template = Template.new!(%{text: "Initial text"})
      updated = Template.update_text(template, "New text")

      assert updated.version == 2
      assert updated.text == "New text"
      assert length(updated.version_history) == 1
      [history_entry] = updated.version_history
      assert history_entry.version == 1
      assert history_entry.text == "Initial text"
    end

    test "rollback_to_version restores previous version" do
      template =
        Template.new!(%{text: "Version 1"})
        |> Template.update_text("Version 2")
        |> Template.update_text("Version 3")

      assert template.version == 3
      assert template.text == "Version 3"

      {:ok, rolled_back} = Template.rollback_to_version(template, 1)
      assert rolled_back.text == "Version 1"
      # Version number stays at current
      assert rolled_back.version == 3
      # Entry is removed from history
      refute Enum.any?(rolled_back.version_history, fn entry -> entry.version == 1 end)
    end

    test "rollback_to_version returns error for non-existent version" do
      template = Template.new!(%{text: "Initial text"})

      assert {:error, "Version 5 not found in history"} =
               Template.rollback_to_version(template, 5)
    end

    test "list_versions returns all versions with current flag" do
      template =
        Template.new!(%{text: "Version 1"})
        |> Template.update_text("Version 2")
        |> Template.update_text("Version 3")

      versions = Template.list_versions(template)
      assert length(versions) == 3

      # Check current version
      [current | history] = versions
      assert current.version == 3
      assert current.current == true

      # Check history versions
      assert Enum.map(history, & &1.version) == [2, 1]
      assert Enum.all?(history, &(&1.current == false))
    end

    test "create_clean_copy resets version history" do
      template =
        Template.new!(%{text: "Version 1"})
        |> Template.update_text("Version 2")
        |> Template.update_text("Version 3")

      clean = Template.create_clean_copy(template)
      assert clean.version == 1
      assert clean.version_history == []
      # Keeps current text
      assert clean.text == "Version 3"
    end
  end
end
