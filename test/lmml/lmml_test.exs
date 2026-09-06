defmodule LmmlTest do
  use ExUnit.Case, async: true

  alias Lmml.Bundle

  describe "the top-level façade" do
    test "open/new_text/new_zip delegate to Lmml.Bundle" do
      {:ok, bundle} = Lmml.new_text("foo", "Hello.")
      assert Bundle.text?(bundle)
      assert Lmml.narrative(bundle) == "Hello."

      {:ok, zip_bundle} = Lmml.new_zip("convo", "See @a.png.", %{"a.png" => "bytes"})
      assert Bundle.zip?(zip_bundle)
      assert [embed] = Lmml.embeds(zip_bundle)
      assert embed.name == "a.png"
    end

    test "the canonical workflow new_zip -> resolve -> render produces content parts" do
      {:ok, bundle} =
        Lmml.new_zip(
          "convo",
          "Here is a photo: @photo.png\n\n@@@settings.yaml\ntheme: dark\n@@@",
          %{"photo.png" => <<1, 2, 3>>}
        )

      {:ok, resolved} = Lmml.resolve(bundle)
      parts = Lmml.render(resolved)

      assert [
               %{"type" => "text", "text" => _text},
               %{"type" => "image_url", "image_url" => %{"url" => _url}},
               %{"type" => "attachment", "name" => "settings.yaml"}
             ] = parts
    end

    test "to_md converts embed syntax to Markdown placeholders" do
      {:ok, bundle} =
        Lmml.new_zip(
          "convo",
          "Check @photo.png and config:\n\n@@@settings.yaml\nmodel: gpt-5\n@@@",
          %{"photo.png" => "png_data"}
        )

      md = Lmml.to_md(bundle)
      assert md =~ "Check [Image: photo.png] and config:"
      assert md =~ "[Attachment: settings.yaml]"
      refute md =~ "@@@settings.yaml"
    end

    test "segment and render_turns delegate to Lmml.Narrative.Segment" do
      {:ok, bundle} =
        Lmml.new_zip(
          "convo",
          "## Turn 1 -- user\nLook at @photo.png.\n\n## Turn 2 -- assistant\nNice!",
          %{"photo.png" => "data"}
        )

      {:ok, resolved} = Lmml.resolve(bundle)
      turns = Lmml.segment(resolved)
      assert length(turns) == 2

      messages = Lmml.render_turns(resolved)
      assert length(messages) == 2
      assert Enum.map(messages, & &1.role) == [:user, :assistant]
    end

    test "pack and inline delegate to Lmml.Pack" do
      {:ok, bundle} = Lmml.new_text("foo", "@@@a.txt\n1\n@@@")
      assert {:ok, packed} = Lmml.pack(bundle)
      assert Bundle.zip?(packed)

      assert {:ok, inlined} = Lmml.inline(packed)
      assert Bundle.text?(inlined)
    end

    test "settings and manifest delegate to Lmml.Settings and Lmml.Manifest" do
      {:ok, bundle} =
        Lmml.new_text(
          "foo",
          "@@@settings.yaml\nmodel: gpt-5\n@@@\n\n@@@manifest.json\n{\"v\": 1}\n@@@"
        )

      assert {:ok, settings} = Lmml.settings(bundle)
      assert Lmml.Settings.get(settings, "model") == "gpt-5"

      assert {:ok, manifest} = Lmml.manifest(bundle)
      assert Lmml.Manifest.get(manifest, "v") == 1
    end

    test "validate delegates to Bundle.validate" do
      {:ok, bundle} = Lmml.new_zip("convo", "See @a.png.", %{"a.png" => "bytes"})
      assert :ok = Lmml.validate(bundle)

      {:ok, broken} = Lmml.new_zip("convo", "See @missing.png.", %{})
      assert {:error, issues} = Lmml.validate(broken)
      assert {:missing_reference, "missing.png"} in issues
    end
  end
end
