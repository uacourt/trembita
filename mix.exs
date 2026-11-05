defmodule Trembita.MixProject do
  use Mix.Project

  def project do
    [
      app: :trembita,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Trembita.Application, []}
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.6"},
      {:plug, "~> 1.16"},
      {:jason, "~> 1.4"},
      {:bpe, "~> 11.4"},
      {:kvs, "~> 13.4"}
    ]
  end
end

