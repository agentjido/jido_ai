# Dotenvy

[![Module Version](https://img.shields.io/hexpm/v/dotenvy.svg)](https://hex.pm/packages/dotenvy)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/dotenvy/)
[![Total Download](https://img.shields.io/hexpm/dt/dotenvy.svg)](https://hex.pm/packages/dotenvy)
[![License](https://img.shields.io/hexpm/l/dotenvy.svg)](https://hex.pm/packages/dotenvy)
[![Last Updated](https://img.shields.io/github/last-commit/fireproofsocks/dotenvy.svg)](https://github.com/fireproofsocks/dotenvy/commits/master)

`Dotenvy` is an Elixir port of the original [dotenv](https://github.com/bkeepers/dotenv) Ruby gem, **compatible with mix and releases**. It is designed to help the development of applications following the principles of the [12-factor app](https://12factor.net/) and its recommendation to store configuration in the environment.

## Installation

Add `dotenvy` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dotenvy, "~> 1.0.0"}
  ]
end
```

It has no dependencies.

## Usage

`Dotenvy` is designed to help configure your application _at runtime_, and one
of the most effective places to do that is inside `config/runtime.exs` (available
since Elixir v1.11).

The `Dotenvy.source/2` function can accept a single file or a list of files.  When combined with `Config.config_env/0` it is easy to load up environment-specific config. A common setup in your `config/runtime.exs` would include a block like the following:

```elixir
# config/runtime.exs
import Config
import Dotenvy

env_dir_prefix = System.get_env("RELEASE_ROOT") || Path.expand("./envs")

source!([
  Path.absname(".env", env_dir_prefix),
  Path.absname(".#{config_env()}.env", env_dir_prefix),
  Path.absname(".#{config_env()}.overrides.env", env_dir_prefix),
  System.get_env()
])
```

The above example would include the `envs/.env` file for shared/default configuration values and then leverage environment-specific `.env` files (e.g. `envs/.dev.env`) to provide environment-specific values. An `envs/.{MIX_ENV}.overrides.env` file would be referenced in the `.gitignore` file to allow developers to override any values a file that is not under version control. System environment variables are given final say over the values via `System.get_env()`.  Think of `Dotenvy.source/2` as a _merge operation_, similar to `Map.merge/2`: the last input takes precedence.

By default, the listed files do not _need_ to exist (you can leverage the `:require_files` option if needed). The `Dotenvy.source/2` function only needs to know where to look. This makes it easy to commit default values while still leaving the door open to developers to override values via their own configuration files.

You control if and how existing system env vars are handled: usually they should take precedence over values defined in `.env` files, so for most apps, the `System.get_env()` should be included as the final input supplied to `source/2`.

Unlike other packages, `Dotenvy` has no opinions about the names or locations of your `.env` files, you just need to pass their paths to `Dotenvy.source/2` or `Dotenvy.source!/2`.

For a simple example, we can load up a `.env` file containing all defaults and an environment-specific file (e.g. `.dev.env`).  Remember to use both [`Path.expand/1`](https://hexdocs.pm/elixir/Path.html#expand/1) and [`Path.absname/2`](https://hexdocs.pm/elixir/Path.html#absname/2) so that the operating system can resolve your file names into fully qualified paths that work when you are developing locally or when your app is running as a release or inside a Livebook.

```elixir
# config/runtime.exs
import Config
import Dotenvy

env_dir_prefix = System.get_env("RELEASE_ROOT") || Path.expand("./envs")

source!([
  Path.absname(".env", env_dir_prefix), 
  Path.absname("#{config_env()}.env", env_dir_prefix), 
  System.get_env()
  ])

config :myapp, MyApp.Repo,
    database: env!("DATABASE", :string!),
    username: env!("USERNAME", :string),
    password: env!("PASSWORD", :string),
    hostname: env!("HOSTNAME", :string!),
    pool_size: env!("POOL_SIZE", :integer),
    adapter: env!("ADAPTER", :module, Ecto.Adapters.Postgres),
    pool: env!("POOL", :module?)
```

And then define your variables in the file(s) to be sourced. `Dotenvy` has no opinions about what you name your files; `.env` is merely a convention.

```env
# .env
DATABASE=myapp_dev
USERNAME=myuser
PASSWORD=mypassword
HOSTNAME=localhost
POOL_SIZE=10
POOL=
```

When you set up your application configuration in this way, you are creating a contract with the environment: `Dotenvy.env!/2` will raise if the required variables have not been set or if the values cannot be properly transformed. This is an approach that works equally well for your day-to-day development and for mix releases.

Read the [Getting Started guide](docs/getting_started.md) for more details.

Refer to the ["dotenv" (`.env`) file format](docs/reference/dotenv-file-format.md) for more examples and features of the supported syntax.

See the `Dotenvy` module documentation on its functions.

### Note for Mix Tasks

If you have authored your own Mix tasks, you must ensure that they load the
application configuration in a way that is compatible with the runtime config.
A good way to do this is to include `Mix.Task.run("app.config")` inside the
`run/1` implementation, e.g.

```elixir
def run(_args) do
  Mix.Task.run("app.config")
  # ...
end
```

If you are dealing with third-party mix tasks that fail to properly load configuration, you may need to manually call `mix app.config` before running them, e.g.

```sh
mix do app.config other.task
```

Defining a task `alias` in `mix.exs` is another way to accomplish this:

```elixir
# mix.exs
defp aliases do
    [
      "other.task": ["app.config", "other.task"]
    ]
```

## Upgrading from v0.5.0 or before

Starting with `Dotenvy` v0.6.0, the precedence of system env variables over parsed `.env` files is not defined; the `:overwrite?` and `:vars` options are no longer supported in `Dotenvy.source/2` and `Dotenvy.source!/2`. Instead, the `source` functions now accept file paths OR maps: this makes the question of variable precedence something that must be explicitly listed. The `source` functions act more like `Map.merge/2`, accumulating values, always giving precedence to the righthand source.

Most users upgrading from v0.5.0 will wish to include `System.get_env()` as the final input to `source/2`.

```elixir
# in dotenvy 0.5.0 or before:
source(["#{config_env()}.env", "#{config_env()}.override.env"])

# should be changed to the following in dotenvy 0.6.0:
source(["#{config_env()}.env", "#{config_env()}.override.env", System.get_env()])
```

If you are relying on [variable interpolation](docs/reference/dotenv-file-format.md) in your `.env` files, you may also need to include `System.get_env()` (or an equivalent subset) _before_ you list your `.env` files.  This is necessary to make values available to the file parser.

```elixir
# in dotenvy 0.5.0 or before:
source(["#{config_env()}.env", "#{config_env()}.override.env"])

# should be changed to the following in dotenvy 0.6.0:
source([System.get_env(), "#{config_env()}.env", "#{config_env()}.override.env", System.get_env()])
```

The change in syntax introduced in v0.6.0 favors a declarative list of sources over opaquely inferred inputs. This also opens the door for compatibility with other value sources, e.g. secure parameter stores.

---------------------------------------------------

Image Attribution: artwork by Beck
