defmodule EnvTest do
  use ExUnit.Case
  doctest Env

  defmacrop generate_name() do
    %Macro.Env{module: mod, function: {fun, arity}} = __CALLER__
    String.upcase("#{mod}.#{fun}/#{arity}")
  end

  setup do
    true = :ets.delete_all_objects(Env)
    :ok
  end

  test "fetch/3" do
    with_env(:app, %{:bar => :baz}, fn ->
      assert {:ok, :baz} == Env.fetch(:env, :bar)
      assert :error      == Env.fetch(:env, :baz)
    end)

    assert {:ok, :baz} == Env.fetch(:env, :bar)
    assert :error      == Env.fetch(:env, :baz)
  end

  test "clear/2" do
    with_env(:app, %{:bar => :baz}, fn ->
      assert {:ok, :baz} == Env.fetch(:env, :bar)
    end)

    assert {:ok, :baz} == Env.fetch(:env, :bar)

    Env.clear(:env, :bar)

    assert :error == Env.fetch(:env, :bar)
  end

  test "clear/1" do
    with_env(:app, %{:bar => :baz}, fn ->
      assert {:ok, :baz} == Env.fetch(:env, :bar)
      assert :error      == Env.fetch(:env, :foo)
    end)

    Env.clear(:env)

    with_env(:app, %{:foo => :baz}, fn ->
      assert :error      == Env.fetch(:env, :bar)
      assert {:ok, :baz} == Env.fetch(:env, :foo)
    end)
  end

  test "refresh/3" do
    assert :error == Env.fetch(:env, :bar)
    with_env(:app, %{:bar => :baz}, fn ->
      assert :error      == Env.fetch(:env, :bar)
      assert {:ok, :baz} == Env.refresh(:env, :bar)
    end)
  end

  test "get/4" do
    with_env(:app, %{:bar => :baz}, fn ->
      assert :baz  == Env.get(:env, :bar)
      assert nil   == Env.get(:env, :baz)
      assert false == Env.get(:env, :foo, false)
    end)
  end

  test "fetch!/3" do
    with_env(:app, %{:bar => :baz}, fn ->
      assert :baz == Env.fetch!(:env, :bar)
      assert_raise RuntimeError, "no configuration value for key :foo of :env", fn ->
        Env.fetch!(:env, :foo)
      end
    end)
  end

  test "config_change/4" do
    with_env(:app, %{:foo => :foo, :bar => :bar}, fn ->
      assert {:ok, :foo} == Env.fetch(:env, :foo)
      assert {:ok, :bar} == Env.fetch(:env, :bar)
      Env.config_change(:env, [{:bar, :baz}], [{:baz, :baz}], [:foo])
    end)
    assert {:ok, :baz} == Env.fetch(:env, :bar)
    assert {:ok, :baz} == Env.fetch(:env, :baz)
    assert :error      == Env.fetch(:env, :foo)
  end

  test "resolve/4 with {:system, name}" do
    name = generate_name()
    with_env(:os, [{name, "foo"}], fn ->
      assert "foo" == Env.resolve({:system, name}, :env, [:key], fn _, x -> x end)
    end)

    assert_raise RuntimeError, ~r"under path \[:key\]", fn ->
      Env.resolve({:system, name}, :env, [:key], fn _, x -> x end)
    end
  end

  test "resolve/4 with {:system, name, default}" do
    name = generate_name()
    assert "foo" == Env.resolve({:system, name, "foo"}, :env, [:key], fn _, x -> x end)

    with_env(:os, [{name, "bar"}], fn ->
      assert "bar" == Env.resolve({:system, name, "foo"}, :env, [:key], fn _, x -> x end)
    end)
  end

  test "resolve/4 with transform" do
    name = generate_name()
    transform = fn [:key], value -> String.to_integer(value) end
    with_env(:os, [{name, "123"}], fn ->
      assert 123 == Env.resolve({:system, name}, :env, [:key], transform)
    end)
  end

  test "resolve/4 walking keywords" do
    name = generate_name()
    transform = fn
      [:key, :sub1],          value -> String.upcase(value)
      [:key, :sub2, :nested], value -> String.downcase(value)
    end

    with_env(:os, [{name, "Foo"}], fn ->
      expected = [sub1: "FOO", sub2: [nested: "foo"]]
      config   = [sub1: {:system, name}, sub2: [nested: {:system, name}]]
      assert expected == Env.resolve(config, :env, [:key], transform)
    end)
  end

  defp with_env(type, env, fun) do
    set_env(type, env)
    try do
      fun.()
    after
      clear_env(type, env)
    end
  end

  defp set_env(:os, env),
    do: Enum.each(env, fn {name, value} -> System.put_env(name, value) end)
  defp set_env(:app, env),
    do: Enum.each(env, fn {name, value} -> Application.put_env(:env, name, value) end)

  defp clear_env(:os, env),
    do: Enum.each(env, fn {name, _} -> :os.unsetenv(to_char_list(name)) end)
  defp clear_env(:app, env),
    do: Enum.each(env, fn {name, _} -> :application.unset_env(:env, name) end)
end
