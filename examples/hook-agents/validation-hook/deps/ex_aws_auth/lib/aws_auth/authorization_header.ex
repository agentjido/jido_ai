defmodule AWSAuth.AuthorizationHeader do
  @moduledoc false

  # http://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-auth-using-authorization-header.html
  def sign(
        access_key,
        secret_key,
        http_method,
        url,
        region,
        service,
        payload,
        headers,
        request_time,
        session_token \\ nil,
        opts \\ []
      ) do
    uri = URI.parse(url)

    params =
      case uri.query do
        nil ->
          Map.new()

        _ ->
          URI.decode_query(uri.query)
      end

    http_method = String.upcase(http_method)
    region = String.downcase(region)
    service = String.downcase(service)

    # Extract options
    unsigned_headers = Keyword.get(opts, :unsigned_headers, [])
    uri_escape_path = Keyword.get(opts, :uri_escape_path, true)
    apply_checksum_header = Keyword.get(opts, :apply_checksum_header, true)

    headers =
      headers
      |> AWSAuth.Utils.filter_unsignable_headers(unsigned_headers)
      |> AWSAuth.Utils.normalize_header_values()
      |> Map.put_new("host", uri.host)

    # Add session token header if provided (for temporary credentials)
    headers =
      if session_token do
        Map.put(headers, "x-amz-security-token", session_token)
      else
        headers
      end

    # Handle unsigned payload
    hashed_payload =
      case payload do
        :unsigned -> :unsigned
        _ -> AWSAuth.Utils.hash_sha256(payload)
      end

    # Only add checksum header if requested (default: true)
    headers =
      if apply_checksum_header do
        checksum_value =
          if hashed_payload == :unsigned, do: "UNSIGNED-PAYLOAD", else: hashed_payload

        Map.put_new(headers, "x-amz-content-sha256", checksum_value)
      else
        headers
      end

    amz_date = request_time |> AWSAuth.Utils.format_time()
    date = request_time |> AWSAuth.Utils.format_date()

    headers = Map.put_new(headers, "x-amz-date", amz_date)

    scope = "#{date}/#{region}/#{service}/aws4_request"

    string_to_sign =
      AWSAuth.Utils.build_canonical_request(
        http_method,
        uri.path || "/",
        params,
        headers,
        hashed_payload,
        uri_escape_path
      )
      |> AWSAuth.Utils.build_string_to_sign(amz_date, scope)

    signature =
      AWSAuth.Utils.build_signing_key(secret_key, date, region, service)
      |> AWSAuth.Utils.build_signature(string_to_sign)

    signed_headers =
      Enum.map(headers, fn {key, _} -> String.downcase(key) end)
      |> Enum.sort(&(&1 < &2))
      |> Enum.join(";")

    auth_header =
      "AWS4-HMAC-SHA256 Credential=#{access_key}/#{scope},SignedHeaders=#{signed_headers},Signature=#{signature}"

    headers
    |> Map.put("authorization", auth_header)
    |> Map.to_list()
  end
end
