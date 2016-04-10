defmodule Env.Mixfile do
  use Mix.Project

  @version "0.1.0"

  def project do
    [app: :env,
     name: "Env",
     version: @version,
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description,
     deps: deps,
     package: package,
     docs: docs]
  end

  def application do
    [applications: [:logger],
     mod: {Env, []}]
  end

  defp deps do
    [{:earmark, "~> 0.2",  only: :dev},
     {:ex_doc,  "~> 0.11", only: :dev}]
  end

  defp description do
    """
    Env is an improved application configuration reader for Elixir.
    """
  end

  defp package do
    [maintainers: ["Michał Muskała"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => "https://github.com/michalmuskala/env"}]
  end

  defp docs do
    [source_ref: "v#{@version}", main: "Env",
     canonical: "http://hexdocs.pm/env",
     source_url: "https://github.com/michalmuskala/env"]
  end
end
