defmodule Lmml.Narrative.ResolverTest do
  use ExUnit.Case, async: true

  alias Lmml.Bundle
  alias Lmml.Embed
  alias Lmml.Narrative.Resolver

  describe "resolve/1" do
    test "resolves an inline embed to its own captured content" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@settings.yaml\nkey: value\n@@@")

      assert {:ok, %Resolver{embeds: [%{embed: embed, content: "key: value\n"}]}} =
               Resolver.resolve(bundle)

      assert embed == Embed.inline("settings.yaml", "key: value\n")
    end

    test "resolves an external reference against the zip's own entries" do
      {:ok, bundle} =
        Bundle.new_zip("convo", "See @image.png here.", %{"image.png" => "bytes"})

      assert {:ok, %Resolver{embeds: [%{embed: embed, content: "bytes"}]}} =
               Resolver.resolve(bundle)

      assert embed == Embed.external("image.png")
    end

    test "carries the bundle's raw narrative text through unchanged" do
      {:ok, bundle} = Bundle.new_text("foo", "Hello world.\n\n@@@a.txt\nhi\n@@@")
      assert {:ok, %Resolver{narrative: narrative}} = Resolver.resolve(bundle)
      assert narrative == "Hello world.\n\n@@@a.txt\nhi\n@@@"
    end

    test "resolves each distinct embed name once, even if mentioned twice" do
      {:ok, bundle} =
        Bundle.new_zip("convo", "@a.png then again @a.png", %{"a.png" => "bytes"})

      assert {:ok, %Resolver{embeds: [%{embed: %Embed{name: "a.png"}}]}} =
               Resolver.resolve(bundle)
    end

    test "resolves multiple distinct embeds in first-occurrence order" do
      {:ok, bundle} =
        Bundle.new_zip("convo", "@a.png then @b.png", %{"a.png" => "1", "b.png" => "2"})

      assert {:ok, %Resolver{embeds: [%{content: "1"}, %{content: "2"}]}} =
               Resolver.resolve(bundle)
    end

    test "fails on the first embed that cannot be resolved, rather than dropping it silently" do
      {:ok, bundle} = Bundle.new_text("foo", "See @missing.png please.")

      assert {:error, {"missing.png", {:unresolvable_reference, "missing.png"}}} =
               Resolver.resolve(bundle)
    end

    test "a bundle with no embeds at all resolves to an empty embeds list" do
      {:ok, bundle} = Bundle.new_text("foo", "Just plain prose.")
      assert {:ok, %Resolver{embeds: []}} = Resolver.resolve(bundle)
    end
  end

  describe "resolve!/1" do
    test "returns the resolved struct directly on success" do
      {:ok, bundle} = Bundle.new_text("foo", "no embeds here")
      assert %Resolver{} = Resolver.resolve!(bundle)
    end

    test "raises when an embed cannot be resolved" do
      {:ok, bundle} = Bundle.new_text("foo", "@missing.png")

      assert_raise RuntimeError, ~r/Failed to resolve lmml narrative/, fn ->
        Resolver.resolve!(bundle)
      end
    end
  end
end
