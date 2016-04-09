defmodule Env do
  use Application

  def start(_type, _args) do
    Env.Supervisor.start_link()
  end

  @spec get(atom, atom, strategy, term) :: term
  def get(app, key, strategy, default \\ nil) do
    case fetch(app, key, strategy) do
      {:ok, value} -> value
      :error       -> default
    end
  end

  @spec fetch(atom, atom, strategy) :: {:ok, term} | :error
  def fetch(app, key, strategy) do
    case lookup(app, key) do
      {:ok, value} ->
        value
      :error ->
        refresh(app, key, strategy)
    end
  end

  @spec fetch!(atom, atom, strategy) :: term | no_return
  def fetch!(app, key, strategy) do
    case fetch(app, key, strategy) do
      {:ok, value} ->
        value
      :error ->
        raise "no value for key #{inspect key} of application " <>
          "#{inspect application}, tried strategy:\n#{inspect strategy}"
    end
  end

  @spec refresh(atom, atom, strategy) :: {:ok, term} | :error
  def refresh(app, key, strategy) do
    store(app, key, apply_strategy(strategy, app, key))
  end

  @spec clear(atom, atom) :: :ok
  def clear(app, key) do
    :ets.delete(Env, {app, key})
    :ok
  end

  @spec clear(atom) :: :ok
  def clear(app) do
    :ets.delete(Env, {app, key})
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

  defp apply_strategy(strategy, app, key, default \\ :error, transform \\ &(&1))

  defp apply_strategy([], _app, _key, default, _transform) do
    default
  end

  defp apply_strategy([{:default, value} | rest], app, key, _default, transform) do
    apply_strategy(rest, app, key, {:ok, value}, transform)
  end

  defp apply_strategy([{:transform, fun} | rest], app, key, default, _transform) do
    apply_strategy(rest, app, key, default, fun)
  end

  defp apply_strategy([alternative | rest], app, key, default, transform) do
    case try_alternative(alternative, app, key) do
      {:ok, value} -> {:ok, transform.(value)}
      :error       -> apply_strategy(rest, app, key, default, transform)
    end
  end

  defp try_alternative(:application, app, key) do
    case :application.get_env(app, key) do
      {:ok, {:system, _} = system} -> try_alternative(system, app, key)
      {:ok, value}                 -> {:ok, value}
      :error                       -> :error
    end
  end

  defp try_alternative(:system, app, key) do
    name = key |> Atom.to_string |> String.upcase
    try_alternative({:system, name}, app, key)
  end

  defp try_alternative({:system, name}, _app, _key) when is_binary(name) do
    case :os.getenv(String.to_char_list(name)) do
      false -> :error
      value -> {:ok, List.to_string(value)}
    end
  end
end
