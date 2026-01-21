defmodule JSV.FormatValidator.Default.Optional.Hostname do
  @moduledoc false
  @spec validate(binary) :: {:ok, binary} | {:error, :invalid_hostname}
  def validate("") do
    {:error, :invalid_hostname}
  end

  def validate(data) do
    # we are catching exits from :idna library so we will use exit instead of
    # throw here.

    # This is a single grapheme
    idn_label_separator = "．"

    if String.starts_with?(data, ".") || String.ends_with?(data, ".") || String.contains?(data, idn_label_separator) do
      exit(:empty_label)
    end

    hostname =
      data
      |> String.to_charlist()
      # If this does not raise, it is mostly valid
      |> :idna.decode()
      # support for idn-hostname would require to_unicode instead of to_ascii.
      # We will return the original string
      |> :idna.to_ascii()
      |> List.to_string()

    if String.length(hostname) > 253 do
      exit(:too_long)
    end

    labels = String.split(hostname, ".")

    if Enum.any?(labels, &bad_hostname_label?/1) do
      exit(:bad_label)
    end

    {:ok, data}
  rescue
    # Punycode error
    FunctionClauseError -> {:error, :invalid_hostname}
  catch
    :exit, _ -> {:error, :invalid_hostname}
  end

  defp bad_hostname_label?("") do
    true
  end

  defp bad_hostname_label?(label) do
    String.starts_with?(label, "-") ||
      String.ends_with?(label, "-") ||
      String.length(label) > 63
  end
end
