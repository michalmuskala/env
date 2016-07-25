defmodule Env do
  @moduledoc """
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

  Result of any lookups (both successful and not) is cached in an ETS table
  - the same mechanism that the Erlang VM uses internally for storing regular
  application configuration. This guarantees that subsequent lookups are as
  fast as are those using functions from `Application` module.

  When you expect the configuration to change, you can use `Env.refresh/3` to
  read the value again ignoring the cache or `Env.clear/1` and `Env.clear/2` in
  order to clear the cache.

  *WARNING*: because Env uses ETS table to store it's cache it is not available
  at compile-time. When you need some compile-time configuration using regular
  `Application.get_env/3` is probably the best option. This should not be a huge
  problem in practice, because configuration should be moved as much as possible
  to the runtime, allowing for easy changes, which is not possible with compile-time
  settings.

  ## Example

  With configuration in `config/config.exs` as follows:

      config :my_app, :key,
        enable_server: true,
        host: [port: {:system, "PORT", 80}],
        secret_key_base: {:system, "SECRET_KEY_BASE"}

  And environment where `PORT` is not set, while `SECRET_KEY_BASE` has value `foo`

  You can access it with `Env` using:

      Env.fetch!(:my_app, :key)
      [enable_server: true, host: [port: 80], secret_key_base: "foo"]

  ## Transformer

  All functions used for accessing the environment accept a `:transformer`
  option. This function can be used to parse any configuration read from system
  environment - all values access from the environment are strings.
  A binary function passes as the `:transformer` will receive path for the current
  key as the first argument, and the value from the environment as the second one.
  Using the example from above, we could use that mechanism to force port to
  always be an integer:

      transformer = fn
        [:key, :host, :port], value -> String.to_integer(value)
        _,                    value -> value
      end

  And pass it to one of the reader functions:

      Env.fetch(:my_app, :key, transformer: transformer)
      {:ok, [enable_server: true, host: [port: 80], secret_key_base: "foo"]}

  """
  use Application

  @type app :: Application.app
  @type key :: Application.key

  @doc false
  def start(_type, _args) do
    Env.Supervisor.start_link()
  end

  @doc """
  Returns value for `key` in `app`'s environment.

  Similar to `fetch/3`, but returns the configuration value if present
  or `default` otherwise. Caches the result for future lookups.

  ## Options

    * `:transform` - transformer function, see module documentation

  ## Example

      iex> Application.put_env(:env, :some_key, :some_value)
      iex> Env.get(:env, :some_key)
      :some_value
      iex> Env.get(:env, :other_key)
      nil
      iex> Env.get(:env, :other_key, false)
      false

  """
  @spec get(app, key, Keyword.t, term) :: term
  def get(app, key, default \\ nil, opts \\ []) when is_list(opts) do
    case fetch(app, key, opts) do
      {:ok, value} -> value
      :error       -> default
    end
  end

  @doc """
  Returns value for `key` in `app`'s environment in a tuple.

  Returns value wrapped in `{:ok, value}` tuple on success or `:error` otherwise.
  Caches the result for future lookups.

  ## Options

    * `:transform` - transformer function, see module documentation

  ## Example

      iex> Application.put_env(:env, :some_key, :some_value)
      iex> Env.fetch(:env, :some_key)
      {:ok, :some_value}
      iex> Env.fetch(:env, :other_key)
      :error

  """
  @spec fetch(app, key, Keyword.t) :: {:ok, term} | :error
  def fetch(app, key, opts \\ []) when is_list(opts) do
    case lookup(app, key) do
      {:ok, value} ->
        value
      :error ->
        refresh(app, key, opts)
    end
  end

  @doc """
  Returns value for `key` in `app`'s environment.

  Similar to `get/4`, but raises when the key is not found.
  Caches the result for future lookups.

  ## Options

    * `:transform` - transformer function, see module documentation

  ## Example

      iex> Application.put_env(:env, :some_key, :some_value)
      iex> Env.fetch!(:env, :some_key)
      :some_value
      iex> Env.fetch!(:env, :other_key)
      ** (RuntimeError) no configuration value for key :other_key of :env

  """
  @spec fetch!(app, key, Keyword.t) :: term | no_return
  def fetch!(app, key, opts \\ []) when is_list(opts) do
    case fetch(app, key, opts) do
      {:ok, value} ->
        value
      :error ->
        raise "no configuration value for key #{inspect key} of #{inspect app}"
    end
  end

  @doc """
  Returns value for `key` in `app`'s environment in a tuple.

  Similar to `fetch/3`, but always reads the value from the application
  environment and searches for system environment references.
  Caches the result for future lookups.

  ## Options

    * `:transform` - transformer function, see module documentation

  ## Example

      iex> Application.put_env(:env, :some_key, :some_value)
      iex> Env.fetch(:env, :some_key)
      {:ok, :some_value}
      iex> Application.put_env(:env, :some_key, :new_value)
      iex> Env.fetch(:env, :some_key)
      {:ok, :some_value}
      iex> Env.refresh(:env, :some_key)
      {:ok, :new_value}

  """
  @spec refresh(app, key, Keyword.t) :: {:ok, term} | :error
  def refresh(app, key, opts \\ []) when is_list(opts) do
    store(app, key, load_and_resolve(app, key, opts))
  end

  @doc """
  Clears the cache for value of `key` in `app`'s environment.
  """
  @spec clear(app, key) :: :ok
  def clear(app, key) do
    :ets.delete(Env, {app, key})
    :ok
  end

  @doc """
  Clears the cache for all values in `app`'s environment.
  """
  @spec clear(app) :: :ok
  def clear(app) do
    :ets.match_delete(Env, {{app, :_}, :_})
    :ok
  end

  @doc """
  Resolves all the Application configuration values and updates
  the Application environment in place.

  You can later access the values with `Application.get_env/3` as usual.

  ## Options

    * `:transform` - transformer function, see module documentation

  """
  @spec resolve_inplace(app, key, Keyword.t) :: :ok
  def resolve_inplace(app, key, opts \\ []) do
    transform = Keyword.get(opts, :transform, fn _, value -> value end)
    value     = Application.fetch_env!(app, key)
    resolved  = resolve(value, app, [key], transform)
    Application.put_env(app, key, resolved)
    :ok
  end

  @doc """
  Function for use in the `:application.config_change/3` callback.

  The callback is called by an application after a code replacement, if
  there are any changes to the configuration parameters.
  This function gives a convenient way to propagate any such changes to Env.

  ## Options

    * `:transform` - transformer function, see module documentation

  ## Example

      def config_change(changed, new, removed) do
        Env.config_change(:my_app, changed, new, removed)
      end

  """
  @spec config_change(app, pairs, pairs, [key], Keyword.t) :: :ok
    when pairs: [{key, term}]
  def config_change(app, changed, new, removed, opts \\ []) do
    transform = Keyword.get(opts, :transform, fn _, value -> value end)

    Enum.each(removed, &clear(app, &1))
    Enum.each(changed, &resolve_and_store(&1, app, transform))
    Enum.each(new,     &resolve_and_store(&1, app, transform))
    :ok
  end

  defp resolve_and_store({key, value}, app, transform) do
    value = resolve(value, app, [key], transform)
    store(app, key, {:ok, value})
  end

  defp lookup(app, key) do
    case :ets.lookup(Env, {app, key}) do
      [{_, value}] -> {:ok, value}
      _            -> :error
    end
  end

  defp store(app, key, value) do
    :ets.insert(Env, {{app, key}, value})
    value
  end

  defp load_and_resolve(app, key, opts) do
    transform = Keyword.get(opts, :transform, fn _, value -> value end)

    case :application.get_env(app, key) do
      {:ok, value} -> {:ok, resolve(value, app, [key], transform)}
      :undefined   -> :error
    end
  end

  @doc false
  def resolve({:system, name, default}, _app, path, transform) do
    case :os.getenv(String.to_char_list(name)) do
      false ->
        default
      value ->
        path = Enum.reverse(path)
        transform.(path, List.to_string(value))
    end
  end
  def resolve({:system, name}, app, path, transform) do
    path = Enum.reverse(path)
    case :os.getenv(String.to_char_list(name)) do
      false ->
        raise "expected environment variable #{name} to be set, as required in " <>
          "configuration of application #{app} under path #{inspect path}"
      value ->
        transform.(path, List.to_string(value))
    end
  end

  def resolve([{key, value} | rest], app, path, transform) when is_atom(key) do
    value = resolve(value, app, [key | path], transform)
    [{key, value} | resolve(rest, app, path, transform)]
  end

  def resolve(value, _app, _path, _transform) do
    value
  end
end
