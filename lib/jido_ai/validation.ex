defmodule Jido.AI.Validation do
  @moduledoc """
  Validation utilities for Jido.AI runtime inputs.

  This module centralizes prompt/input validation, callback validation, and
  resource-bound checks used across actions and strategies.
  """

  @type validation_result :: :ok | {:error, reason :: term()}
  @type prompt :: String.t()
  @type callback :: function()

  @max_prompt_length 5_000
  @max_input_length 100_000
  @max_hard_turns 50
  @callback_timeout 5_000

  @dangerous_bytes [
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    11,
    12,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31
  ]

  @doc """
  Validates prompt input and returns a sanitized version.
  """
  @spec validate_and_sanitize_prompt(prompt()) :: {:ok, prompt()} | {:error, atom()}
  def validate_and_sanitize_prompt(nil), do: {:error, :empty_prompt}

  def validate_and_sanitize_prompt(prompt) when is_binary(prompt) do
    with :ok <- validate_prompt_length(prompt),
         :ok <- validate_prompt_content(prompt),
         {:ok, sanitized} <- sanitize_prompt(prompt) do
      {:ok, String.trim(sanitized)}
    end
  end

  def validate_and_sanitize_prompt(_), do: {:error, :invalid_prompt_type}

  @doc """
  Validates prompt input without transforming it.
  """
  @spec validate_prompt(prompt()) :: validation_result()
  def validate_prompt(prompt) when is_binary(prompt) do
    with :ok <- validate_prompt_length(prompt),
         :ok <- validate_prompt_content(prompt) do
      validate_prompt_injection_safe(prompt)
    end
  end

  def validate_prompt(_), do: {:error, :invalid_prompt_type}

  @doc """
  Validates custom prompts used for system-level behavior.
  """
  @spec validate_custom_prompt(prompt(), keyword()) :: {:ok, prompt()} | {:error, atom()}
  def validate_custom_prompt(custom_prompt, opts \\ [])

  def validate_custom_prompt(nil, _opts), do: {:error, :empty_custom_prompt}
  def validate_custom_prompt("", _opts), do: {:error, :empty_custom_prompt}

  def validate_custom_prompt(custom_prompt, opts) when is_binary(custom_prompt) do
    max_length = Keyword.get(opts, :max_length, @max_prompt_length)
    allow_patterns = Keyword.get(opts, :allow_injection_patterns, false)

    with :ok <- validate_custom_length(custom_prompt, max_length),
         :ok <- validate_content_characters(custom_prompt),
         {:ok, sanitized} <- sanitize_custom_prompt(custom_prompt, allow_patterns) do
      {:ok, String.trim(sanitized)}
    end
  end

  def validate_custom_prompt(_, _opts), do: {:error, :invalid_custom_prompt_type}

  @doc """
  Validates callback arity and type.
  """
  @spec validate_callback(callback()) :: validation_result()
  def validate_callback(callback) when is_function(callback, 1), do: :ok
  def validate_callback(callback) when is_function(callback, 2), do: :ok
  def validate_callback(callback) when is_function(callback, 3), do: :ok
  def validate_callback(callback) when is_function(callback), do: {:error, :invalid_callback_arity}
  def validate_callback(_), do: {:error, :invalid_callback_type}

  @doc """
  Validates and wraps callbacks with timeout protection.
  """
  @spec validate_and_wrap_callback(callback(), keyword()) ::
          {:ok, callback()} | {:error, atom()}
  def validate_and_wrap_callback(callback, opts \\ [])

  def validate_and_wrap_callback(callback, opts) when is_function(callback) do
    with :ok <- validate_callback(callback) do
      timeout = Keyword.get(opts, :timeout, @callback_timeout)
      task_supervisor = Keyword.get(opts, :task_supervisor, Jido.TaskSupervisor)

      with {:ok, resolved_supervisor} <- validate_task_supervisor(task_supervisor) do
        wrapped = wrap_with_timeout(callback, timeout, resolved_supervisor)
        {:ok, wrapped}
      end
    end
  end

  def validate_and_wrap_callback(_callback, _opts), do: {:error, :invalid_callback_type}

  @doc """
  Validates and caps requested max-turn counts.
  """
  @spec validate_max_turns(integer()) :: {:ok, integer()} | {:error, atom()}
  def validate_max_turns(max_turns) when is_integer(max_turns) and max_turns >= 0 do
    {:ok, min(max_turns, @max_hard_turns)}
  end

  def validate_max_turns(_), do: {:error, :invalid_max_turns}

  @doc """
  Returns the hard upper bound for max-turn validation.
  """
  @spec max_hard_turns() :: integer()
  def max_hard_turns, do: @max_hard_turns

  @doc """
  Validates generic string input with length and control-byte checks.
  """
  @spec validate_string(String.t() | nil, keyword()) :: {:ok, String.t()} | {:error, atom()}
  def validate_string(input, opts \\ [])

  def validate_string(nil, _opts), do: {:error, :empty_string}

  def validate_string(input, opts) when is_binary(input) do
    max_length = Keyword.get(opts, :max_length, @max_input_length)
    allow_empty? = Keyword.get(opts, :allow_empty, false)
    trim? = Keyword.get(opts, :trim, true)
    processed = if trim?, do: String.trim(input), else: input

    with :ok <- validate_not_empty(processed, allow_empty?),
         :ok <- validate_string_length(processed, max_length),
         :ok <- validate_string_characters(processed) do
      {:ok, processed}
    end
  end

  def validate_string(_, _opts), do: {:error, :invalid_string_type}

  @doc """
  Returns the maximum allowed custom prompt length.
  """
  @spec max_prompt_length() :: integer()
  def max_prompt_length, do: @max_prompt_length

  @doc """
  Returns the maximum allowed general input length.
  """
  @spec max_input_length() :: integer()
  def max_input_length, do: @max_input_length

  @doc """
  Returns the default callback timeout in milliseconds.
  """
  @spec callback_timeout() :: integer()
  def callback_timeout, do: @callback_timeout

  defp validate_prompt_length(prompt) do
    byte_size = byte_size(prompt)

    cond do
      byte_size == 0 -> {:error, :empty_prompt}
      byte_size > @max_input_length -> {:error, :prompt_too_long}
      true -> :ok
    end
  end

  defp validate_prompt_content(prompt) do
    case find_dangerous_character(prompt) do
      nil -> :ok
      char -> {:error, {:dangerous_character, char}}
    end
  end

  defp find_dangerous_character(<<>>), do: nil

  defp find_dangerous_character(<<char, _rest::binary>>) when char in @dangerous_bytes do
    <<char>>
  end

  defp find_dangerous_character(<<_char, rest::binary>>) do
    find_dangerous_character(rest)
  end

  defp validate_prompt_injection_safe(prompt) do
    if contains_injection_pattern?(prompt), do: {:error, :prompt_injection_detected}, else: :ok
  end

  defp sanitize_prompt(prompt) do
    if contains_injection_pattern?(prompt) do
      {:error, :prompt_injection_detected}
    else
      sanitized =
        prompt
        |> String.replace(~r/\r\n/, "\n")
        |> String.replace(~r/\t/, "  ")

      {:ok, sanitized}
    end
  end

  defp contains_injection_pattern?(prompt) do
    Enum.any?(injection_patterns(), fn pattern -> Regex.match?(pattern, prompt) end)
  end

  defp injection_patterns do
    [
      ~r/ignore\s+(the\s+)?(previous|above)\s+instructions/i,
      ~r/ignore\s+all\s+(previous|above)?\s+instructions/i,
      ~r/override\s+(your\s+)?system/i,
      ~r/disregard\s+(the\s+)?(previous|above)\s+instructions/i,
      ~r/disregard\s+all\s+(previous|above)?\s+instructions/i,
      ~r/pay\s+no\s+attention\s+to\s+(the\s+)?(previous|above)/i,
      ~r/forget\s+(everything|all\s+instructions)/i,
      ~r/\n\n\s*(SYSTEM|ASSISTANT|AI|INSTRUCTION|HUMAN):\s*/i,
      ~r/###\s*(SYSTEM|ASSISTANT|AI|INSTRUCTION|HUMAN):\s*/i,
      ~r/---\s*(SYSTEM|ASSISTANT|AI|INSTRUCTION|HUMAN):\s*/i,
      ~r/you\s+are\s+now\s+a\s+(different|new)/i,
      ~r/act\s+as\s+if\s+you\s+are/i,
      ~r/pretend\s+(to\s+be|you\s+are)/i,
      ~r/switch\s+roles?\s+with\s+me/i,
      ~r/roleplay\s+as\s+(a\s+)?(different|new|dangerous)/i,
      ~r/\{[^}]*"role"\s*:\s*"system"/i,
      ~r/<[^>]*system[^>]*>/i,
      ~r/dan\s+\d+\.?\d*/i,
      ~r/(developer|admin|root)\s+mode/i,
      ~r/unrestricted\s+mode/i,
      ~r/bypass\s+(all\s+)?(safety|filters?|security)/i,
      ~r/(print|output|display|say|echo)\s+(everything|all\s+the\s+(above|text|instructions))/i,
      ~r/(repeat|return|show)\s+your\s+(system\s+)?prompt/i,
      ~r/translate\s+(this|the\s+above)\s+to\s+(base64|binary|hex)/i
    ]
  end

  defp validate_custom_length(prompt, max_length) do
    if byte_size(prompt) > max_length, do: {:error, :custom_prompt_too_long}, else: :ok
  end

  defp validate_content_characters(prompt) do
    case find_dangerous_character(prompt) do
      nil -> :ok
      char -> {:error, {:dangerous_character, char}}
    end
  end

  defp sanitize_custom_prompt(prompt, allow_patterns?) do
    if allow_patterns? do
      {:ok, prompt}
    else
      if contains_injection_pattern?(prompt), do: {:error, :custom_prompt_injection_detected}, else: {:ok, prompt}
    end
  end

  defp validate_task_supervisor(supervisor) when is_pid(supervisor) do
    if Process.alive?(supervisor), do: {:ok, supervisor}, else: {:error, :missing_task_supervisor}
  end

  defp validate_task_supervisor(supervisor) when is_atom(supervisor) and not is_nil(supervisor) do
    if is_pid(Process.whereis(supervisor)), do: {:ok, supervisor}, else: {:error, :missing_task_supervisor}
  end

  defp validate_task_supervisor(_), do: {:error, :invalid_task_supervisor}

  defp wrap_with_timeout(callback, timeout, task_supervisor) do
    fn arg ->
      case start_callback_task(task_supervisor, callback, arg) do
        {:ok, task} ->
          try do
            case Task.yield(task, timeout) || Task.shutdown(task) do
              {:ok, task_result} -> task_result
              {:exit, _} -> {:error, :callback_timeout}
              nil -> {:error, :callback_timeout}
            end
          after
            Process.demonitor(task.ref, [:flush])
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp start_callback_task(task_supervisor, callback, arg) do
    try do
      {:ok, Task.Supervisor.async_nolink(task_supervisor, fn -> callback.(arg) end)}
    catch
      :exit, {:noproc, _} -> {:error, :missing_task_supervisor}
      :exit, _ -> {:error, :callback_execution_failed}
    end
  end

  defp validate_not_empty("", false), do: {:error, :empty_string}
  defp validate_not_empty(_, _), do: :ok

  defp validate_string_length(str, max_length) do
    if String.length(str) > max_length, do: {:error, :string_too_long}, else: :ok
  end

  defp validate_string_characters(str) do
    case find_dangerous_character(str) do
      nil -> :ok
      char -> {:error, {:dangerous_character, char}}
    end
  end
end
