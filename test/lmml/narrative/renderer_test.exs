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
  end
end
