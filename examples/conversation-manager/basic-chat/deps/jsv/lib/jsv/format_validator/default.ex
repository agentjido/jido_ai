defmodule JSV.FormatValidator.Default do
  import JSV.FormatValidator.Default.Optional
  alias JSV.FormatValidator.Default.Optional

  @moduledoc false

  @behaviour JSV.FormatValidator

  @supports_duration Code.ensure_loaded?(Duration)

  @formats [
             "ipv4",
             "ipv6",
             "unknown",
             "regex",
             "date",
             "date-time",
             "time",
             "hostname",
             "uri",
             "uri-reference",
             "uuid",
             "email",
             "iri",
             "iri-reference",
             "uri-template",
             "json-pointer",
             "relative-json-pointer",
             optional_support("duration", @supports_duration)
           ]
           |> :lists.flatten()
           |> Enum.sort()

  @impl true
  def supported_formats do
    @formats
  end

  # Default formats in the specification only apply to strings
  @impl true
  def applies_to_type?(_any_format, data) do
    is_binary(data)
  end

  @impl true
  def validate_cast("date-time", data) do
    case DateTime.from_iso8601(data) do
      {:ok, dt, _} ->
        if String.contains?(data, " ") do
          {:error, :invalid_format}
        else
          {:ok, dt}
        end

      {:error, _} = err ->
        err
    end
  end

  def validate_cast("date", data) do
    Date.from_iso8601(data)
  end

  if @supports_duration do
    def validate_cast("duration", data) do
      # JSON schema adheres closely to the spec, the duration cannot mix Week and
      # other P-level elements. But we are allowing it because Elixir allows it,
      # we do not want to put arbitrary limit to capabilities.
      Duration.from_iso8601(data)
    end
  end

  def validate_cast("time", data) do
    Time.from_iso8601(String.replace(data, "z", "Z"))
  end

  def validate_cast("ipv4", data) do
    :inet.parse_strict_address(String.to_charlist(data))
  end

  def validate_cast("ipv6", data) do
    # JSON schema spec does not support zone info suffix in ipv6
    with {:ok, {_, _, _, _, _, _, _, _} = ipv6} <- :inet.parse_strict_address(String.to_charlist(data)),
         false <- String.contains?(data, "%") do
      {:ok, ipv6}
    else
      _ -> {:error, :invalid_ipv6}
    end
  end

  def validate_cast("uuid", data) do
    Optional.UUID.parse_uuid(data)
  end

  def validate_cast("regex", data) do
    Regex.compile(data)
  end

  def validate_cast("unknown", data) do
    {:ok, data}
  end

  def validate_cast("email", data) do
    Optional.EmailAddress.parse_email_address(data)
  end

  def validate_cast("hostname", data) do
    Optional.Hostname.validate(data)
  end

  def validate_cast("iri", data) do
    Optional.IRI.parse_iri(data)
  end

  def validate_cast("iri-reference", data) do
    Optional.IRI.parse_iri_reference(data)
  end

  def validate_cast("uri", data) do
    Optional.URI.parse_uri(data)
  end

  def validate_cast("uri-reference", data) do
    Optional.URI.parse_uri_reference(data)
  end

  def validate_cast("uri-template", data) do
    Texture.UriTemplate.parse(data)
  end

  def validate_cast("json-pointer", data) do
    Optional.JSONPointer.parse_json_pointer(data)
  end

  def validate_cast("relative-json-pointer", data) do
    Optional.JSONPointer.parse_relative_json_pointer(data)
  end
end
