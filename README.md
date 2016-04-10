# Env

Env is an improved application configuration reader for Elixir.

Env allows you to access easily the configuration of your application
similar to what `Application.get_env/3` does, but understands the
`{:system, "NAME"}` convention of using system environment variables
in application configuration.

When Env initially retrieves the configuration it will walk recursively
any keyword lists and properly replace any occurrences of:
`{:system, "NAME"}` or `{:system, "NAME", default}` with value extracted
from the environment using `System.get_env("NAME")`.

When a tuple without default value is used, but the environment variable is
not set an exception will be raised.

Result of any lookups (both successful and not) is cached in an ETS table -
the same mechanism that the Erlang VM uses internally for storing regular
application configuration. This guarantees that subsequent lookups are as
fast as are those using functions from `Application` module.

When you expect the configuration to change, you can use `Env.refresh/3` to
read the value again ignoring the cache or `Env.clear/1` and `Env.clear/2` in
order to clear the cache.

## Installation

The package can be installed as:

  1. Add env to your list of dependencies in `mix.exs`:

        def deps do
          [{:env, "~> 0.1"}]
        end

  2. Ensure env is started before your application:

        def application do
          [applications: [:env]]
        end


## Example

With configuration in `config/config.exs` as follows:

```elixir
config :my_app, :key,
  enable_server: true,
  host: [port: {:system, "PORT", 80}],
  secret_key_base: {:system, "SECRET_KEY_BASE"}
```

And environment where `PORT` is not set, while `SECRET_KEY_BASE` has value `foo`

You can access it with `Env` using:

```elixir
Env.fetch!(:my_app, :key)
[enable_server: true, host: [port: 80], secret_key_base: "foo"]
```

## Transformer

All functions used for accessing the environment accept a `:transformer`
option. This function can be used to parse any configuration read from system
environment - all values access from the environment are strings.
A binary function passes as the `:transformer` will receive path for the current
key as the first argument, and the value from the environment as the second one.
Using the example from above, we could use that mechanism to force port to
always be an integer:

```elixir
transformer = fn
  [:key, :host, :port], value -> String.to_integer(value)
  _,                    value -> value
end
```

And pass it to one of the reader functions:

```elixir
Env.fetch(:my_app, :key, transformer: transformer)
{:ok, [enable_server: true, host: [port: 80], secret_key_base: "foo"]}
```

## License

Copyright 2016 Michał Muskała

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
