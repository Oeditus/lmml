defmodule Lmml.Narrative.RendererTest do
  use ExUnit.Case, async: true

  alias Lmml.Bundle
  alias Lmml.Narrative.Renderer
  alias Lmml.Narrative.Resolver

  describe "render/1" do
    test "a bundle with no embeds renders to a single text part" do
      {:ok, bundle} = Bundle.new_text("foo", "Just plain prose.")
      {:ok, resolved} = Resolver.resolve(bundle)

      assert Renderer.render(resolved) == [%{"type" => "text", "text" => "Just plain prose."}]
    end

    test "mixed prose, an external image reference, and an inline settings embed" do
      {:ok, bundle} =
        Bundle.new_zip(
          "convo",
          "Here is a photo: @photo.png\n\n@@@settings.yaml\ntheme: dark\n@@@",
          %{"photo.png" => <<1, 2, 3>>}
        )

      {:ok, resolved} = Resolver.resolve(bundle)
      parts = Renderer.render(resolved)

      assert [
               %{"type" => "text", "text" => text},
               %{"type" => "image_url", "image_url" => %{"url" => image_url}},
               %{"type" => "attachment", "name" => "settings.yaml"} = attachment
             ] = parts

      assert text == Bundle.narrative(bundle)
      assert image_url == "data:image/png;base64," <> Base.encode64(<<1, 2, 3>>)
      assert attachment["mime"] == "application/yaml"
      assert attachment["content"] == "theme: dark\n"
    end

    test "image extensions become image_url parts with the correct mime type" do
      {:ok, bundle} = Bundle.new_zip("convo", "@a.jpg", %{"a.jpg" => "bytes"})
      {:ok, resolved} = Resolver.resolve(bundle)

      assert [_text, %{"type" => "image_url", "image_url" => %{"url" => url}}] =
               Renderer.render(resolved)

      assert String.starts_with?(url, "data:image/jpeg;base64,")
    end

    test "an unrecognized extension falls back to a generic octet-stream attachment" do
      {:ok, bundle} = Bundle.new_zip("convo", "@a.bin", %{"a.bin" => "bytes"})
      {:ok, resolved} = Resolver.resolve(bundle)

      assert [_text, %{"type" => "attachment", "mime" => "application/octet-stream"}] =
               Renderer.render(resolved)
    end
  end

  describe "mime_type/1 and image?/1" do
    test "recognizes common image extensions" do
      assert Renderer.mime_type("a.png") == "image/png"
      assert Renderer.mime_type("a.JPG") == "image/jpeg"
      assert Renderer.image?("a.gif")
    end

    test "recognizes common text extensions as non-image" do
      assert Renderer.mime_type("a.json") == "application/json"
      refute Renderer.image?("a.json")
    end

    test "falls back to a generic mime type for unknown extensions" do
      assert Renderer.mime_type("a.xyz") == "application/octet-stream"
      refute Renderer.image?("a.xyz")
    end

    test "recognizes the expanded document/audio/video/code extension set" do
      assert Renderer.mime_type("a.pdf") == "application/pdf"
      assert Renderer.mime_type("a.csv") == "text/csv"
      assert Renderer.mime_type("a.log") == "text/plain"
      assert Renderer.mime_type("a.diff") == "text/x-diff"
      assert Renderer.mime_type("a.mp3") == "audio/mpeg"
      assert Renderer.mime_type("a.mp4") == "video/mp4"
      assert Renderer.mime_type("a.svg") == "image/svg+xml"
      assert Renderer.image?("a.svg")
      refute Renderer.image?("a.pdf")
    end
  end

  describe "render/2 with :max_embed_bytes" do
    test "drops embeds whose content exceeds the per-embed byte budget" do
      {:ok, bundle} =
        Bundle.new_zip("convo", "@big.txt and @small.txt", %{
          "big.txt" => String.duplicate("x", 100),
          "small.txt" => "tiny"
        })

      {:ok, resolved} = Resolver.resolve(bundle)

      parts = Renderer.render(resolved, max_embed_bytes: 50)

      assert [
               %{"type" => "text"},
               %{"type" => "attachment", "name" => "small.txt"}
             ] = parts
    end

    test "with no limit, render/2 keeps every embed (same as render/1)" do
      {:ok, bundle} = Bundle.new_zip("convo", "@a.txt", %{"a.txt" => "hello"})
      {:ok, resolved} = Resolver.resolve(bundle)

      assert Renderer.render(resolved, []) == Renderer.render(resolved)
    end
  end

  describe "total_embed_bytes/1" do
    test "sums the resolved content of every embed, not the narrative" do
      {:ok, bundle} =
        Bundle.new_zip("convo", "a long narrative @a.txt and @b.txt", %{
          "a.txt" => "12345",
          "b.txt" => "678"
        })

      {:ok, resolved} = Resolver.resolve(bundle)
      assert Renderer.total_embed_bytes(resolved) == 8
    end

    test "is 0 for a narrative with no embeds" do
      {:ok, bundle} = Bundle.new_text("foo", "just prose")
      {:ok, resolved} = Resolver.resolve(bundle)
      assert Renderer.total_embed_bytes(resolved) == 0
    end
  end
end
