defmodule Lmml.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/Oeditus/lmml"
  @homepage_url "https://oeditus.com"

  def project do
    [
      app: :lmml,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_add_apps: [:mix],
        plt_core_path: "priv/plts",
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      name: "Lmml",
      source_url: @source_url,
      homepage_url: @homepage_url
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
        "coveralls.json": :test
      ]
    ]
  end

  defp description do
    "A Markdown-superset markup language for structuring LLM conversations, " <>
      "with a self-contained text form (.lmml) and a zip-archive form (.lmmlz) " <>
      "for carrying referenced files alongside the narrative."
  end

  defp package do
    [
      name: "lmml",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      maintainers: ["Oeditus Team"],
      links: %{
        "GitHub" => @source_url,
        "Homepage" => @homepage_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Documentation" => "https://hexdocs.pm/lmml"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "stuff/img/logo-48.png",
      assets: %{"stuff/img" => "assets"},
      extras: extras(),
      source_url: @source_url,
      source_ref: "v#{@version}",
      homepage_url: @homepage_url,
      formatters: ["html", "epub"],
      authors: ["Oeditus Team"],
      canonical: "https://hexdocs.pm/lmml",
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp extras do
    [
      "README.md",
      "docs/LANGUAGE_REFERENCE.md": [title: "Language Reference"],
      LICENSE: [title: "License"],
      "CHANGELOG.md": [title: "Changelog"]
    ]
  end

  defp aliases do
    [
      quality: ["format", "credo --strict", "dialyzer"],
      "quality.ci": [
        "format --check-formatted",
        "credo --strict",
        "dialyzer"
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # >= 0.12.2 for the Syntax.merge/2 :settings fix and the block
      # `escape:` property lmml relies on -- see Lmml.Narrative.Syntax.
      {:md, "~> 0.12.2"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
