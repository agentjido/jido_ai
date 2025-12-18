defmodule AWSAuth.Req do
  @moduledoc """
  Req plugin for AWS Signature V4 authentication.

  This module provides seamless integration between `ex_aws_auth` and the
  `Req` HTTP client library. It automatically signs requests with AWS Signature V4
  without requiring manual header manipulation.

  ## Usage

      # Load credentials from environment
      creds = AWSAuth.Credentials.from_env()

      # Attach to a Req request
      Req.new(url: url, method: :post, body: body)
      |> AWSAuth.Req.attach(credentials: creds, service: "bedrock")
      |> Req.request()

      # Or create a reusable client
      client =
        Req.new(base_url: "https://bedrock-runtime.us-east-1.amazonaws.com")
        |> AWSAuth.Req.attach(credentials: creds, service: "bedrock")

      # Make multiple requests
      Req.post!(client, url: "/model/my-model/invoke", json: params)

  ## Options

    * `:credentials` - (required) `AWSAuth.Credentials` struct or keyword list with:
      * `:access_key_id` - AWS Access Key ID
      * `:secret_access_key` - AWS Secret Access Key
      * `:session_token` - AWS Session Token (optional)
      * `:region` - AWS region (optional, defaults to "us-east-1")

    * `:service` - (required) AWS service name (e.g., "s3", "bedrock", "lambda")

    * `:region` - AWS region (optional, overrides region from credentials)

  ## How it Works

  The plugin adds a request step that:

  1. Extracts the request method, URL, headers, and body
  2. Normalizes Req's list-valued headers to string values for signing
  3. Signs the request using AWS Signature V4
  4. Returns headers in Req's expected format (`%{key => [value]}`)

  ## Examples

      # Basic usage with environment credentials
      creds = AWSAuth.Credentials.from_env()

      response =
        Req.new()
        |> AWSAuth.Req.attach(credentials: creds, service: "s3")
        |> Req.get!(url: "https://my-bucket.s3.amazonaws.com/object")

      # With explicit credentials
      creds = %AWSAuth.Credentials{
        access_key_id: "AKIAIOSFODNN7EXAMPLE",
        secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-west-2"
      }

      response =
        Req.new(url: url, method: :post, json: data)
        |> AWSAuth.Req.attach(credentials: creds, service: "bedrock")
        |> Req.request!()

      # With session token (STS temporary credentials)
      creds = %AWSAuth.Credentials{
        access_key_id: "ASIAIOSFODNN7EXAMPLE",
        secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        session_token: "FwoGZXIvYXdzEBYaDHhBTEMPLESessionToken123",
        region: "us-east-1"
      }

      response =
        Req.new()
        |> AWSAuth.Req.attach(credentials: creds, service: "lambda")
        |> Req.post!(url: lambda_url, json: payload)

      # Override region
      response =
        Req.new()
        |> AWSAuth.Req.attach(
          credentials: creds,
          service: "s3",
          region: "eu-west-1"
        )
        |> Req.get!(url: "https://my-bucket.s3.eu-west-1.amazonaws.com/object")
  """

  alias AWSAuth.Credentials

  @doc """
  Attaches AWS Signature V4 signing to a Req request.

  ## Parameters

    * `request` - A `Req.Request` struct
    * `opts` - Keyword list of options (see module docs for details)

  ## Returns

  A `Req.Request` with the AWS signing step prepended.

  ## Examples

      creds = AWSAuth.Credentials.from_env()

      request =
        Req.new(url: url)
        |> AWSAuth.Req.attach(credentials: creds, service: "bedrock")
  """
  @spec attach(Req.Request.t(), keyword()) :: Req.Request.t()
  def attach(%Req.Request{} = request, opts) when is_list(opts) do
    credentials = get_credentials!(opts)
    service = get_service!(opts)
    region = Keyword.get(opts, :region, credentials.region || "us-east-1")

    request
    |> Req.Request.prepend_request_steps(
      aws_sigv4: fn req ->
        sign_request(req, credentials, service, region)
      end
    )
  end

  # Sign a Req request with AWS Signature V4
  defp sign_request(req, credentials, service, region) do
    method = String.upcase(to_string(req.method))
    url = URI.to_string(req.url)

    # Normalize headers - Req uses %{key => [value]} format
    # Convert to %{key => value} for signing
    headers =
      Map.new(req.headers, fn {k, v} ->
        {k, if(is_list(v), do: List.first(v), else: v)}
      end)

    body = req.body || ""

    # Sign using the credentials struct API with :req return format
    signed_headers =
      AWSAuth.sign_authorization_header(
        credentials,
        method,
        url,
        service,
        headers: headers,
        payload: body,
        region: region,
        return_format: :req
      )

    # Update request with signed headers
    %{req | headers: signed_headers}
  end

  # Extract credentials from options, supporting both Credentials struct and keyword list
  defp get_credentials!(opts) do
    case Keyword.fetch(opts, :credentials) do
      {:ok, %Credentials{} = creds} ->
        creds

      {:ok, creds} when is_list(creds) or is_map(creds) ->
        Credentials.from_map(creds)

      :error ->
        raise ArgumentError, """
        Missing required :credentials option.

        Please provide credentials as either:

        1. AWSAuth.Credentials struct:
           AWSAuth.Req.attach(request, credentials: AWSAuth.Credentials.from_env(), service: "s3")

        2. Keyword list or map:
           AWSAuth.Req.attach(request,
             credentials: [
               access_key_id: "...",
               secret_access_key: "...",
               region: "us-east-1"
             ],
             service: "s3"
           )
        """
    end
  end

  # Extract service from options
  defp get_service!(opts) do
    case Keyword.fetch(opts, :service) do
      {:ok, service} when is_binary(service) ->
        service

      {:ok, other} ->
        raise ArgumentError, """
        Invalid :service option. Expected a string, got: #{inspect(other)}

        Example:
          AWSAuth.Req.attach(request, credentials: creds, service: "bedrock")
        """

      :error ->
        raise ArgumentError, """
        Missing required :service option.

        Please specify the AWS service name:
          AWSAuth.Req.attach(request, credentials: creds, service: "bedrock")

        Common services: "s3", "bedrock", "lambda", "dynamodb", "sns", "sqs"
        """
    end
  end
end
