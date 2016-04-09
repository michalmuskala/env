defmodule Env.Supervisor do
  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(_) do
    _ = :ets.new(Env, [:set, :public, :named_table, read_concurrency: true])
    supervise([], strategy: :one_for_one)
  end
end
