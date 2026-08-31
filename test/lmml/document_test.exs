defmodule Lmml.DocumentTest do
  use ExUnit.Case, async: true

  alias Lmml.Document
  alias Lmml.Embed

  describe "parse/1" do
    test "a plain document with no lmml syntax has an empty embed list" do
      {:ok, document} = Document.parse("Just a plain paragraph.")
      assert document.embeds == []
    end

    test "collects a top-level reference" do
      {:ok, document} = Document.parse("See @image.png please.")
      assert document.embeds == [Embed.external("image.png")]
    end

    test "collects a top-level inline embed" do
      {:ok, document} = Document.parse("@@@settings.yaml\nkey: value\n@@@")
      assert document.embeds == [Embed.inline("settings.yaml", "key: value\n")]
    end

    test "collects multiple embeds in document order" do
      doc = """
      First @a.png then more.

      @@@b.yaml
      x: 1
      @@@

      And finally @c.png.
      """

      {:ok, document} = Document.parse(doc)

      assert document.embeds == [
               Embed.external("a.png"),
               Embed.inline("b.yaml", "x: 1\n"),
               Embed.external("c.png")
             ]
    end

    test "finds a reference nested inside emphasis/list/blockquote structures" do
      doc = "- an item mentioning *@nested.png* inside emphasis"
      {:ok, document} = Document.parse(doc)

      assert document.embeds == [Embed.external("nested.png")]
    end

    test "an inline embed's content survives quotes, ampersands, and angle brackets verbatim" do
      # Md's `block:` category (which the @@@ embed fence is built on, same
      # as Default's own ``` code fence) HTML-entity-escapes these five
      # characters by default as it captures block content; the `@@@` entry
      # in Lmml.Narrative.Syntax sets `escape: false` (Md >= 0.12.2) so an
      # embed's content always matches the bytes actually written between
      # the fences, with no post-processing needed here.
      json = ~s({"key": "a & b <tag> 'quoted'"})
      {:ok, document} = Document.parse("@@@data.json\n#{json}\n@@@")

      assert document.embeds == [Embed.inline("data.json", json <> "\n")]
      assert document.ast == [{:lmml_embed, %{name: "data.json"}, [json <> "\n"]}]
    end
  end

  describe "embed/2" do
    test "finds an embed by name" do
      # The embed fence must be its own block (like any fenced construct --
      # see Lmml.Narrative.Syntax's moduledoc), so it's on its own line
      # here rather than glued to the preceding reference.
      {:ok, document} = Document.parse("@a.png and:\n\n@@@b.yaml\nx\n@@@")

      assert {:ok, %Embed{name: "a.png"}} = Document.embed(document, "a.png")
      assert {:ok, %Embed{name: "b.yaml"}} = Document.embed(document, "b.yaml")
    end

    test "returns an error for a name that isn't mentioned" do
      {:ok, document} = Document.parse("nothing special here")
      assert {:error, :not_found} = Document.embed(document, "missing.png")
    end

    test "returns the first occurrence when a reference repeats" do
      {:ok, document} = Document.parse("@a.png ... and again @a.png")
      assert {:ok, %Embed{name: "a.png"}} = Document.embed(document, "a.png")
    end
  end

  describe "embed_names/1" do
    test "deduplicates repeated references" do
      {:ok, document} = Document.parse("@a.png then @a.png then @b.png")
      assert Document.embed_names(document) == ["a.png", "b.png"]
    end
  end

  describe "external_embeds/1 and inline_embeds/1" do
    test "partitions embeds by kind" do
      doc = "@a.png\n\n@@@b.yaml\nx\n@@@"
      {:ok, document} = Document.parse(doc)

      assert Document.external_embeds(document) == [Embed.external("a.png")]
      assert Document.inline_embeds(document) == [Embed.inline("b.yaml", "x\n")]
    end
  end
end
