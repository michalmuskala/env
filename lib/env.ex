defmodule Env do
  use Application

  @doc false
  def start(_type, _args) do
    Env.Supervisor.start_link()
  end

  @spec get(atom, atom, Kyeword.t, term) :: term
  def get(app, key, default \\ nil, opts \\ []) when is_list(opts) do
    case fetch(app, key, opts) do
      {:ok, value} -> value
      :error       -> default
    end
  end

  @spec fetch(atom, atom, Kyeword.t) :: {:ok, term} | :error
  def fetch(app, key, opts \\ []) when is_list(opts) do
    case lookup(app, key) do
      {:ok, value} ->
        value
      :error ->
        refresh(app, key, opts)
    end
  end

  @spec fetch!(atom, atom, Keyword.t) :: term | no_return
  def fetch!(app, key, opts \\ []) when is_list(opts) do
    case fetch(app, key, opts) do
      {:ok, value} ->
        value
      :error ->
        raise "no configuration value for key #{inspect key} of #{inspect app}"
    end
  end

  @spec refresh(atom, atom, Keyword.t) :: {:ok, term} | :error
  def refresh(app, key, opts \\ []) when is_list(opts) do
    store(app, key, load_and_resolve(app, key, opts))
  end

  @spec clear(atom, atom) :: :ok
  def clear(app, key) do
    :ets.delete(Env, {app, key})
    :ok
  end

  @spec clear(atom) :: :ok
  def clear(app) do
    :ets.match_delete(Env, {{app, :_}, :_})
    :ok
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
