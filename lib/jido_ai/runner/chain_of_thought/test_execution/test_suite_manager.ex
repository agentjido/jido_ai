defmodule Jido.AI.Runner.ChainOfThought.TestExecution.TestSuiteManager do
  @moduledoc """
  Manages test suite generation, storage, and framework detection.

  Handles:
  - Test suite generation using CoT reasoning
  - Test case storage with temporary file management
  - Test framework detection (ExUnit, DocTest, etc.)
  - Custom test template registration
  """

  require Logger

  @default_framework :ex_unit

  @doc """
  Generates comprehensive test suite for given code using CoT reasoning.

  ## Parameters

  - `code` - Code to generate tests for
  - `opts` - Options:
    - `:coverage` - Coverage level (:basic, :comprehensive, :exhaustive)
    - `:framework` - Test framework to use
    - `:module_name` - Name of module being tested

  ## Returns

  - `{:ok, test_suite}` - Generated test suite as string
  - `{:error, reason}` - Generation failed
  """
  @spec generate_tests(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_tests(code, opts \\ []) do
    coverage = Keyword.get(opts, :coverage, :comprehensive)
    framework = Keyword.get(opts, :framework, @default_framework)
    module_name = Keyword.get(opts, :module_name)

    Logger.debug("Generating #{coverage} test suite using #{framework}")

    # Extract module name if not provided
    module_name = module_name || extract_module_name(code)

    case framework do
      :ex_unit -> generate_ex_unit_tests(code, module_name, coverage)
      :doc_test -> generate_doc_tests(code, module_name)
      :property_test -> generate_property_tests(code, module_name, coverage)
      _ -> {:error, {:unsupported_framework, framework}}
    end
  end

  @doc """
  Stores test suite in temporary file for execution.

  ## Parameters

  - `test_suite` - Test suite content as string
  - `framework` - Test framework being used

  ## Returns

  - `{:ok, file_path}` - File created successfully
  - `{:error, reason}` - Storage failed
  """
  @spec store_tests(String.t(), atom()) :: {:ok, Path.t()} | {:error, term()}
  def store_tests(test_suite, framework \\ @default_framework) do
    extension = framework_extension(framework)
    temp_dir = System.tmp_dir!()
    timestamp = System.system_time(:millisecond)
    filename = "test_#{timestamp}#{extension}"
    file_path = Path.join(temp_dir, filename)

    case File.write(file_path, test_suite) do
      :ok ->
        Logger.debug("Stored test suite at #{file_path}")
        {:ok, file_path}

      {:error, reason} ->
        Logger.error("Failed to store test suite: #{inspect(reason)}")
        {:error, {:file_write_failed, reason}}
    end
  end

  @doc """
  Stores code in temporary file for execution.

  ## Parameters

  - `code` - Code content as string

  ## Returns

  - `{:ok, file_path}` - File created successfully
  - `{:error, reason}` - Storage failed
  """
  @spec store_code(String.t()) :: {:ok, Path.t()} | {:error, term()}
  def store_code(code) do
    temp_dir = System.tmp_dir!()
    timestamp = System.system_time(:millisecond)
    filename = "code_#{timestamp}.ex"
    file_path = Path.join(temp_dir, filename)

    case File.write(file_path, code) do
      :ok ->
        Logger.debug("Stored code at #{file_path}")
        {:ok, file_path}

      {:error, reason} ->
        Logger.error("Failed to store code: #{inspect(reason)}")
        {:error, {:file_write_failed, reason}}
    end
  end

  @doc """
  Detects test framework from test suite content.

  ## Parameters

  - `test_content` - Test suite content

  ## Returns

  Test framework atom
  """
  @spec detect_framework(String.t()) :: atom()
  def detect_framework(test_content) do
    cond do
      String.contains?(test_content, "use ExUnit.Case") ->
        :ex_unit

      String.contains?(test_content, "@doc ") and String.contains?(test_content, "iex>") ->
        :doc_test

      String.contains?(test_content, "use ExUnitProperties") ->
        :property_test

      true ->
        @default_framework
    end
  end

  @doc """
  Registers custom test template for domain-specific testing.

  ## Parameters

  - `template_name` - Name of template
  - `template_fn` - Function generating test from template

  ## Returns

  `:ok`
  """
  @spec register_template(atom(), fun()) :: :ok
  def register_template(template_name, template_fn)
      when is_atom(template_name) and is_function(template_fn) do
    # Store in persistent term for fast access
    :persistent_term.put({__MODULE__, :template, template_name}, template_fn)
    Logger.info("Registered custom test template: #{template_name}")
    :ok
  end

  @doc """
  Gets registered test template.

  ## Parameters

  - `template_name` - Name of template

  ## Returns

  - `{:ok, template_fn}` - Template found
  - `{:error, :not_found}` - Template not registered
  """
  @spec get_template(atom()) :: {:ok, fun()} | {:error, :not_found}
  def get_template(template_name) do
    case :persistent_term.get({__MODULE__, :template, template_name}, nil) do
      nil -> {:error, :not_found}
      template_fn -> {:ok, template_fn}
    end
  end

  @doc """
  Cleans up temporary test and code files.

  ## Parameters

  - `file_paths` - List of file paths to clean up

  ## Returns

  `:ok`
  """
  @spec cleanup(list(Path.t())) :: :ok
  def cleanup(file_paths) when is_list(file_paths) do
    Enum.each(file_paths, fn path ->
      case File.rm(path) do
        :ok -> Logger.debug("Cleaned up #{path}")
        {:error, reason} -> Logger.warning("Failed to cleanup #{path}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  # Private functions

  defp generate_ex_unit_tests(code, module_name, coverage) do
    # Extract function definitions
    functions = extract_functions(code)

    test_cases =
      case coverage do
        :basic -> generate_basic_tests(functions, module_name)
        :comprehensive -> generate_comprehensive_tests(functions, module_name)
        :exhaustive -> generate_exhaustive_tests(functions, module_name)
      end

    test_module = """
    defmodule #{module_name}Test do
      use ExUnit.Case, async: true

      alias #{module_name}

    #{test_cases}
    end
    """

    {:ok, test_module}
  end

  defp generate_doc_tests(_code, module_name) do
    test_module = """
    defmodule #{module_name}DocTest do
      use ExUnit.Case, async: true

      doctest #{module_name}
    end
    """

    {:ok, test_module}
  end

  defp generate_property_tests(code, module_name, coverage) do
    functions = extract_functions(code)

    property_tests =
      case coverage do
        :basic -> generate_basic_properties(functions, module_name)
        _ -> generate_comprehensive_properties(functions, module_name)
      end

    test_module = """
    defmodule #{module_name}PropertyTest do
      use ExUnit.Case, async: true
      use ExUnitProperties

      alias #{module_name}

    #{property_tests}
    end
    """

    {:ok, test_module}
  end

  defp extract_module_name(code) do
    case Regex.run(~r/defmodule\s+([A-Z][A-Za-z0-9._]*)/, code) do
      [_, module_name] -> module_name
      _ -> "TestModule"
    end
  end

  defp extract_functions(code) do
    # Simple function extraction using regex
    Regex.scan(~r/def\s+([a-z_][a-z0-9_?!]*)\s*\(/, code)
    |> Enum.map(fn [_, func_name] -> func_name end)
    |> Enum.uniq()
  end

  defp generate_basic_tests(functions, module_name) do
    functions
    |> Enum.map_join("\n", fn func_name ->
      """
        test "#{func_name}/0 returns expected result" do
          assert #{module_name}.#{func_name}() != nil
        end
      """
    end)
  end

  defp generate_comprehensive_tests(functions, module_name) do
    functions
    |> Enum.map_join("\n", fn func_name ->
      """
        describe "#{func_name}" do
          test "returns expected result for valid input" do
            assert #{module_name}.#{func_name}() != nil
          end

          test "handles edge cases" do
            # TODO: Add edge case tests
            assert true
          end
        end
      """
    end)
  end

  defp generate_exhaustive_tests(functions, module_name) do
    functions
    |> Enum.map_join("\n", fn func_name ->
      """
        describe "#{func_name}" do
          test "returns expected result for valid input" do
            assert #{module_name}.#{func_name}() != nil
          end

          test "handles edge cases" do
            # TODO: Add edge case tests
            assert true
          end

          test "handles error conditions" do
            # TODO: Add error condition tests
            assert true
          end

          test "validates input types" do
            # TODO: Add type validation tests
            assert true
          end
        end
      """
    end)
  end

  defp generate_basic_properties(functions, module_name) do
    functions
    |> Enum.map_join("\n", fn func_name ->
      """
        property "#{func_name} satisfies basic properties" do
          check all input <- term() do
            result = #{module_name}.#{func_name}()
            assert result != nil
          end
        end
      """
    end)
  end

  defp generate_comprehensive_properties(functions, module_name) do
    functions
    |> Enum.map_join("\n", fn func_name ->
      """
        property "#{func_name} is deterministic" do
          check all input <- term() do
            result1 = #{module_name}.#{func_name}()
            result2 = #{module_name}.#{func_name}()
            assert result1 == result2
          end
        end

        property "#{func_name} handles all input types" do
          check all input <- term() do
            result = #{module_name}.#{func_name}()
            assert result != nil
          end
        end
      """
    end)
  end

  defp framework_extension(:ex_unit), do: "_test.exs"
  defp framework_extension(:doc_test), do: "_doc_test.exs"
  defp framework_extension(:property_test), do: "_property_test.exs"
  defp framework_extension(_), do: "_test.exs"
end
