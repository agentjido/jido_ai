defmodule AWSAuth.Credentials do
  @moduledoc """
  AWS credentials struct for authentication.

  This struct holds AWS credentials for signing requests. It can be created
  manually or loaded from environment variables.

  ## Fields

    * `:access_key_id` - AWS Access Key ID (required)
    * `:secret_access_key` - AWS Secret Access Key (required)
    * `:session_token` - AWS Session Token for temporary credentials (optional)
    * `:region` - AWS region (optional, defaults to "us-east-1")

  ## Examples

      # Create credentials manually
      creds = %AWSAuth.Credentials{
        access_key_id: "AKIAIOSFODNN7EXAMPLE",
        secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1"
      }

      # Load from environment variables
      creds = AWSAuth.Credentials.from_env()

      # Load from environment with fallback
      creds = AWSAuth.Credentials.from_env() || %AWSAuth.Credentials{
        access_key_id: "...",
        secret_access_key: "..."
      }

  ## Environment Variables

  `from_env/0` reads the following environment variables:

    * `AWS_ACCESS_KEY_ID` - Access key ID
    * `AWS_SECRET_ACCESS_KEY` - Secret access key
    * `AWS_SESSION_TOKEN` - Session token (optional)
    * `AWS_REGION` or `AWS_DEFAULT_REGION` - Region (optional)
  """

  @type t :: %__MODULE__{
          access_key_id: String.t() | nil,
          region: String.t() | nil,
          secret_access_key: String.t() | nil,
          session_token: String.t() | nil
        }

  defstruct [
    :access_key_id,
    :region,
    :secret_access_key,
    :session_token
  ]

  @doc """
  Creates credentials from environment variables.

  Returns `nil` if required environment variables are not set.

  ## Examples

      # With environment variables set
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
      System.put_env("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
      System.put_env("AWS_REGION", "us-west-2")

      creds = AWSAuth.Credentials.from_env()
      # => %AWSAuth.Credentials{
      #      access_key_id: "AKIAIOSFODNN7EXAMPLE",
      #      secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
      #      region: "us-west-2",
      #      session_token: nil
      #    }

      # Without required environment variables
      System.delete_env("AWS_ACCESS_KEY_ID")
      AWSAuth.Credentials.from_env()
      # => nil
  """
  @spec from_env() :: t() | nil
  def from_env do
    access_key_id = System.get_env("AWS_ACCESS_KEY_ID")
    secret_access_key = System.get_env("AWS_SECRET_ACCESS_KEY")

    # Return nil if required credentials are missing
    if access_key_id && secret_access_key do
      %__MODULE__{
        access_key_id: access_key_id,
        region: System.get_env("AWS_REGION") || System.get_env("AWS_DEFAULT_REGION"),
        secret_access_key: secret_access_key,
        session_token: System.get_env("AWS_SESSION_TOKEN")
      }
    end
  end

  @doc """
  Creates credentials from a keyword list or map.

  ## Examples

      AWSAuth.Credentials.from_map(%{
        access_key_id: "AKIAIOSFODNN7EXAMPLE",
        secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1"
      })
  """
  @spec from_map(map() | keyword()) :: t()
  def from_map(map_or_keyword) do
    map = if Keyword.keyword?(map_or_keyword), do: Map.new(map_or_keyword), else: map_or_keyword

    %__MODULE__{
      access_key_id: map[:access_key_id] || map["access_key_id"],
      region: map[:region] || map["region"],
      secret_access_key: map[:secret_access_key] || map["secret_access_key"],
      session_token: map[:session_token] || map["session_token"]
    }
  end
end
