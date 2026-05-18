defmodule Reed.HtmlTest do
  use ExUnit.Case
  # doctest

  import Reed.Transformers

  describe "html stream handler" do
    test "parses rss in html" do
      stream = stream_feed("blog-jim-nielsen-com-feed.html")

      assert {:ok, rss} =
               Reed.stream(stream,
                 feed_url: "https://blog.jim-nielsen.com/feed.json",
                 transform: collect() |> limit(2) |> pipeline()
               )

      assert "html+mf2" == rss.flavor
      assert Enum.count(rss.private.items) == 2
    end
  end

  defp stream_feed(name) do
    Path.join(__DIR__, "../../feeden/priv/examples/#{name}")
    |> Path.expand()
    |> File.stream!()
  end
end
