defmodule Reed.MixProject do
  use Mix.Project

  def project do
    [
      app: :reed,
      description:
        "Streaming RSS parser with a built-in `Req` plugin for network-enabled chunked streaming.",
      version: "0.2.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      cli: cli()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:atomic_map, "~> 0.9"},
      {:jason, "~> 1.4"},
      {:microformats2, "~> 1.0"},
      {:mime, "~> 2.0"},
      {:saxy, "~> 1.6"},
      {:req, "~> 0.5", optional: true},
      {:ex_doc, "~> 0.31.0", only: :docs}
    ]
  end

  defp package do
    [
      maintainers: ["Andres Alejos"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/acalejos/reed"}
    ]
  end

  defp cli do
    [preferred_envs: [docs: :docs, "hex.publish": :docs]]
  end

  defp docs do
    [
      main: "Reed"
    ]
  end
end
