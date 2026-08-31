defmodule Lmml.PackTest do
  use ExUnit.Case, async: true

  alias Lmml.Bundle
  alias Lmml.Pack

  describe "pack/2" do
    test "externalizes an inline embed into a real zip entry and rewrites the reference" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@settings.yaml\nkey: value\n@@@")

      assert {:ok, packed} = Pack.pack(bundle)
      assert Bundle.zip?(packed)
      assert Bundle.narrative(packed) == "@settings.yaml"
      assert Bundle.entries(packed) == ["settings.yaml"]
      assert {:ok, "key: value\n"} = Bundle.embed(packed, "settings.yaml")
    end

    test "leaves surrounding prose untouched" do
      {:ok, bundle} = Bundle.new_text("foo", "Before.\n\n@@@a.txt\nhello\n@@@\n\nAfter.\n")

      {:ok, packed} = Pack.pack(bundle)
      assert Bundle.narrative(packed) == "Before.\n\n@a.txt\n\nAfter.\n"
    end

    test "leaves an already-external reference exactly as it is" do
      {:ok, bundle} = Bundle.new_zip("convo", "See @a.png here.", %{"a.png" => "bytes"})

      {:ok, packed} = Pack.pack(bundle)
      assert Bundle.narrative(packed) == "See @a.png here."
      assert {:ok, "bytes"} = Bundle.embed(packed, "a.png")
    end

    test "merges existing zip entries with newly externalized inline embeds" do
      {:ok, bundle} =
        Bundle.new_zip("convo", "@a.png then:\n\n@@@b.yaml\nx: 1\n@@@", %{"a.png" => "bytes"})

      {:ok, packed} = Pack.pack(bundle)
      assert Bundle.entries(packed) |> Enum.sort() == ["a.png", "b.yaml"]
      assert {:ok, "bytes"} = Bundle.embed(packed, "a.png")
      assert {:ok, "x: 1\n"} = Bundle.embed(packed, "b.yaml")
    end

    test "a dangling reference in the source is left dangling in the result" do
      {:ok, bundle} = Bundle.new_text("foo", "See @missing.png please.")

      {:ok, packed} = Pack.pack(bundle)
      assert Bundle.entries(packed) == []
      assert {:error, {:missing_entry, "missing.png"}} = Bundle.embed(packed, "missing.png")
    end

    test "defaults the resulting bundle's name to the source bundle's own name" do
      {:ok, bundle} = Bundle.new_text("foo", "plain")
      {:ok, packed} = Pack.pack(bundle)
      assert Bundle.name(packed) == "foo.lmml"
    end

    test "an explicit name overrides the default" do
      {:ok, bundle} = Bundle.new_text("foo", "plain")
      {:ok, packed} = Pack.pack(bundle, "renamed")
      assert Bundle.name(packed) == "renamed.lmml"
    end

    test "an embed name that cannot safely become a zip entry name is rejected" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@../evil.txt\nx\n@@@")
      assert {:error, {:unsafe_entry, "../evil.txt"}} = Pack.pack(bundle)
    end

    test "multiple distinct inline embeds are all externalized" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@a.txt\n1\n@@@\n\n@@@b.txt\n2\n@@@")

      {:ok, packed} = Pack.pack(bundle)
      assert Bundle.narrative(packed) == "@a.txt\n\n@b.txt"
      assert Bundle.entries(packed) |> Enum.sort() == ["a.txt", "b.txt"]
    end
  end

  describe "pack!/2" do
    test "returns the packed bundle directly on success" do
      {:ok, bundle} = Bundle.new_text("foo", "plain")
      assert %Bundle{} = Pack.pack!(bundle)
    end

    test "raises on failure" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@../evil.txt\nx\n@@@")

      assert_raise RuntimeError, ~r/Failed to pack lmml bundle/, fn ->
        Pack.pack!(bundle)
      end
    end
  end

  describe "inline/2" do
    test "strips the reference sigil in place and appends a proper fenced block" do
      {:ok, bundle} = Bundle.new_zip("convo", "See @notes.txt here.", %{"notes.txt" => "hello"})

      assert {:ok, inlined} = Pack.inline(bundle)
      assert Bundle.text?(inlined)
      assert Bundle.narrative(inlined) == "See notes.txt here.\n\n@@@notes.txt\nhello@@@"
      assert {:ok, "hello"} = Bundle.embed(inlined, "notes.txt")
    end

    test "leaves an already-inline embed exactly as it is" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@a.txt\nhello\n@@@")

      {:ok, inlined} = Pack.inline(bundle)
      assert Bundle.narrative(inlined) == "@@@a.txt\nhello\n@@@"
    end

    test "drops a zip entry that nothing in the narrative references" do
      {:ok, bundle} = Bundle.new_zip("convo", "No references here.", %{"orphan.png" => "bytes"})

      {:ok, inlined} = Pack.inline(bundle)
      assert Bundle.narrative(inlined) == "No references here."
      assert Bundle.embeds(inlined) == []
    end

    test "fails when an external reference cannot be resolved, rather than partially inlining" do
      {:ok, bundle} = Bundle.new_zip("convo", "See @missing.png please.", %{})
      assert {:error, {"missing.png", {:missing_entry, "missing.png"}}} = Pack.inline(bundle)
    end

    test "does not confuse a shorter reference name with a longer, unrelated one" do
      {:ok, bundle} =
        Bundle.new_zip("convo", "See @a.png and @a.png.bak too.", %{
          "a.png" => "short",
          "a.png.bak" => "long"
        })

      {:ok, inlined} = Pack.inline(bundle)

      assert Bundle.narrative(inlined) ==
               "See a.png and a.png.bak too.\n\n@@@a.png.bak\nlong@@@\n\n@@@a.png\nshort@@@"

      assert {:ok, "short"} = Bundle.embed(inlined, "a.png")
      assert {:ok, "long"} = Bundle.embed(inlined, "a.png.bak")
    end

    test "defaults the resulting bundle's name to the source bundle's own name" do
      {:ok, bundle} = Bundle.new_zip("convo", "plain", %{})
      {:ok, inlined} = Pack.inline(bundle)
      assert Bundle.name(inlined) == "convo.lmml"
    end

    test "rejects inlining genuinely binary content instead of crashing the parser" do
      # A real image (or any non-UTF-8 bytes) can't be spliced into the
      # narrative's own UTF-8 text -- Md's parser has no defined behavior
      # for an invalid byte sequence embedded mid-text and would crash
      # rather than fail cleanly, so this is rejected up front instead.
      not_utf8 = <<0xFF, 0xFE, 0x00, 0x01>>
      {:ok, bundle} = Bundle.new_zip("convo", "See @image.png here.", %{"image.png" => not_utf8})

      assert {:error, {"image.png", :not_utf8}} = Pack.inline(bundle)
    end
  end

  describe "inline!/2" do
    test "returns the inlined bundle directly on success" do
      {:ok, bundle} = Bundle.new_zip("convo", "plain", %{})
      assert %Bundle{} = Pack.inline!(bundle)
    end

    test "raises on failure" do
      {:ok, bundle} = Bundle.new_zip("convo", "@missing.png", %{})

      assert_raise RuntimeError, ~r/Failed to inline lmml bundle/, fn ->
        Pack.inline!(bundle)
      end
    end
  end

  describe "round-trip: pack then inline" do
    test "produces a bundle whose embeds resolve to the same content as the original" do
      {:ok, original} =
        Bundle.new_text(
          "convo",
          "Intro prose.\n\n@@@settings.yaml\ntheme: dark\n@@@\n\nMore prose after.\n"
        )

      {:ok, packed} = Pack.pack(original)
      {:ok, roundtripped} = Pack.inline(packed)

      original_names = original |> Bundle.embeds() |> Enum.map(& &1.name) |> Enum.sort()
      roundtripped_names = roundtripped |> Bundle.embeds() |> Enum.map(& &1.name) |> Enum.sort()
      assert original_names == roundtripped_names

      for name <- original_names do
        assert Bundle.embed(original, name) == Bundle.embed(roundtripped, name)
      end
    end

    test "is idempotent for a bundle mixing an inline embed and an external reference" do
      {:ok, original} =
        Bundle.new_zip("convo", "@a.png then:\n\n@@@b.txt\nhello\n@@@", %{"a.png" => "bytes"})

      {:ok, packed} = Pack.pack(original)
      {:ok, inlined} = Pack.inline(packed)
      {:ok, repacked} = Pack.pack(inlined)

      assert Bundle.entries(repacked) |> Enum.sort() == Bundle.entries(packed) |> Enum.sort()
      assert {:ok, "bytes"} = Bundle.embed(repacked, "a.png")
      assert {:ok, "hello\n"} = Bundle.embed(repacked, "b.txt")
    end
  end
end
