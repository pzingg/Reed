defmodule Reed.GetTest do
  use ExUnit.Case
  # doctest

  import Reed.Transformers

  describe "get json" do
    test "collects items" do
      url = "https://daringfireball.net/feeds/json"

      rss =
        url
        |> Reed.get!(transform: collect() |> limit(2) |> pipeline())
        |> Req.Response.get_private(:rss)

      assert rss.private.count == 2
    end

    test "normalizes items" do
      url = "https://daringfireball.net/feeds/json"

      rss =
        url
        |> Reed.get!(transform: collect() |> limit(2) |> pipeline(), normalize_rss: true)
        |> Req.Response.get_private(:rss)

      assert rss.private.count == 2
      links = Map.get(rss.feed_info, "links")
      assert is_list(links)
    end

    test "converts to common RSS structs" do
      url = "https://daringfireball.net/feeds/json"

      feed =
        url
        |> Reed.get!(transform: collect() |> limit(2) |> pipeline())
        |> Req.Response.get_private(:rss)
        |> Reed.Basic.Transformer.to_feed()

      assert Enum.count(feed.items) == 2
    end
  end

  describe "get xml" do
    test "collects items" do
      url = "https://daringfireball.net/feeds/main"

      rss =
        url
        |> Reed.get!(transform: collect() |> limit(2) |> pipeline())
        |> Req.Response.get_private(:rss)

      assert rss.private.count == 2
    end

    test "normalizes items" do
      url = "https://daringfireball.net/feeds/main"

      rss =
        url
        |> Reed.get!(transform: collect() |> limit(2) |> pipeline(), normalize_rss: true)
        |> Req.Response.get_private(:rss)

      assert rss.private.count == 2
      links = Map.get(rss.feed_info, "links")
      assert is_list(links)
    end

    test "collects limited item data" do
      url = "https://daringfireball.net/feeds/main"

      transform =
        transform(&Map.take(&1, ["description", "title", "published"]))
        |> collect()
        |> limit(2)
        |> pipeline()

      rss =
        url
        |> Reed.get!(transform: transform)
        |> Req.Response.get_private(:rss)

      assert rss.private.count == 2
    end

    test "converts to common RSS structs" do
      url = "https://daringfireball.net/feeds/main"

      feed =
        url
        |> Reed.get!(transform: collect() |> limit(2) |> pipeline())
        |> Req.Response.get_private(:rss)
        |> Reed.Basic.Transformer.to_feed()

      assert Enum.count(feed.items) == 2
    end
  end
end
