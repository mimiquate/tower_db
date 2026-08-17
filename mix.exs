defmodule TowerDB.MixProject do
  use Mix.Project

  def project do
    [
      app: :tower_db,
      version: "0.6.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      package: package()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tower, "~> 0.7"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.17"},
      {:uuid_v7, "~> 0.6"}
    ]
  end

  defp package do
    [
      organization: "mimiquate",
      licenses: ["Apache-2.0"],
      links: %{}
    ]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
