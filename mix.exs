defmodule RockSolid.MixProject do
  use Mix.Project

  @source_url "https://github.com/IgnacioGoldchluk/rock_solid"
  @version "0.0.3"

  def project do
    [
      app: :rock_solid,
      version: @version,
      elixir: "~> 1.16",
      description: description(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:zoi, "~> 0.17"},
      {:jsv, "~> 0.18.3"},
      {:pythonx, "~> 0.4.0"},
      {:nimble_options, "~> 1.1"},
      {:req, "~> 0.5.0", only: [:dev, :test]},
      # Data generation
      {:stream_data, "~> 1.0"},
      {:more_stream_data, "~> 0.8"},
      {:plug, "~> 1.0", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false, warn_if_outdated: true}
    ]
  end

  defp docs do
    [
      main: "RockSolid",
      extras: ["README.md", "CHANGELOG.md", "ROADMAP.md"] ++ extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules(),
      filter_modules: fn module, _meta ->
        module in [
          RockSolid,
          RockSolid.Resolution.Resolvers.DummyResolver,
          RockSolid.Resolution.Resolver
        ]
      end
    ]
  end

  defp extras do
    [
      "guides/recommendations.md"
    ]
  end

  defp groups_for_extras do
    [
      Guides: ~r/guides\/.?/,
      Dev: ~r/.*/
    ]
  end

  defp groups_for_modules do
    [
      "Main API": [RockSolid],
      Resolvers: [
        RockSolid.Resolution.Resolvers.DummyResolver,
        RockSolid.Resolution.Resolver
      ]
    ]
  end

  defp description do
    "Data generation from JSON Schema"
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Ignacio Goldchluk"],
      source_ref: "v#{@version}",
      links: %{"GitHub" => @source_url}
    ]
  end
end
