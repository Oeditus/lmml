defmodule Lmml.EmbedTest do
  use ExUnit.Case, async: true

  alias Lmml.Embed

  describe "inline/2 and external/1,2" do
    test "inline/2 builds an {:inline, content} embed" do
      assert Embed.inline("settings.yaml", "key: value") == %Embed{
               name: "settings.yaml",
               content: {:inline, "key: value"}
             }
    end

    test "external/1 defaults the entry name to the embed's own name" do
      assert Embed.external("image.png") == %Embed{
               name: "image.png",
               content: {:external, "image.png"}
             }
    end

    test "external/2 allows the entry name to differ from the display name" do
      assert Embed.external("logo", "assets/logo.png") == %Embed{
               name: "logo",
               content: {:external, "assets/logo.png"}
             }
    end
  end

  describe "inline?/1 and external?/1" do
    test "an inline embed is inline? and not external?" do
      embed = Embed.inline("a.txt", "hello")
      assert Embed.inline?(embed)
      refute Embed.external?(embed)
    end

    test "an external embed is external? and not inline?" do
      embed = Embed.external("a.png")
      refute Embed.inline?(embed)
      assert Embed.external?(embed)
    end
  end
end
