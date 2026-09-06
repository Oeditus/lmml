defmodule Mix.Tasks.Lmml.Render do
  use Mix.Task

  @shortdoc "Renders a bundle into LLM-ready content parts"

  @moduledoc """
  Opens a bundle, resolves its embeds, and renders its narrative and assets
  into typed content parts ready for LLM APIs.

      mix lmml.render SOURCE [--json] [--max-embed-bytes BYTES]

  Options:

    * `--json` - output the content parts directly as JSON.
    * `--max-embed-bytes BYTES` - omit any embed exceeding `BYTES`.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _} =
      OptionParser.parse(args,
        switches: [json: :boolean, max_embed_bytes: :integer],
        aliases: [j: :json, m: :max_embed_bytes]
      )

    case positional do
      [source] -> do_render(source, opts)
      _ -> Mix.raise("Usage: mix lmml.render SOURCE [--json] [--max-embed-bytes BYTES]")
    end
  end

  defp do_render(source, opts) do
    resolved = open_and_resolve(source)
    parts = Lmml.render(resolved, build_render_opts(opts))
    output_parts(parts, source, opts)
  end

  defp open_and_resolve(source) do
    bundle =
      try do
        Lmml.open!(source)
      rescue
        e -> Mix.raise("Failed to open #{source}: #{Exception.message(e)}")
      end

    case Lmml.resolve(bundle) do
      {:ok, res} -> res
      {:error, reason} -> Mix.raise("Failed to resolve #{source}: #{inspect(reason)}")
    end
  end

  defp build_render_opts(opts) do
    case Keyword.fetch(opts, :max_embed_bytes) do
      {:ok, limit} -> [max_embed_bytes: limit]
      :error -> []
    end
  end

  defp output_parts(parts, source, opts) do
    if opts[:json] do
      json_bytes = :json.encode(parts)
      Mix.shell().info(to_string(json_bytes))
    else
      Mix.shell().info("Rendered #{length(parts)} content part(s) from #{source}:")
      Enum.each(parts, &print_part/1)
    end
  end

  defp print_part(%{"type" => "text", "text" => text}) do
    Mix.shell().info("  - [text] #{byte_size(text || "")} bytes")
  end

  defp print_part(%{"type" => "image_url"}) do
    Mix.shell().info("  - [image_url] data URI payload")
  end

  defp print_part(%{"type" => "attachment"} = part) do
    name = part["name"]
    mime = part["mime"]
    size = byte_size(part["content"] || "")
    Mix.shell().info("  - [attachment] #{name} (#{mime}, #{size} bytes)")
  end

  defp print_part(%{"type" => other}) do
    Mix.shell().info("  - [#{other}]")
  end
end
