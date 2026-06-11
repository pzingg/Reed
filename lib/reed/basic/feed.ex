defmodule Reed.Basic.Feed do
  require Logger

  @derive Jason.Encoder
  defstruct authors: nil,
            id: nil,
            language: nil,
            subtitle: nil,
            summary: nil,
            title: nil,
            updated: nil,
            categories: [],
            image: nil,
            links: [],
            items: [],
            data: %{}

  @type t :: %__MODULE__{
          authors: nil | String.t(),
          id: nil | String.t(),
          language: nil | String.t(),
          subtitle: nil | String.t(),
          summary: nil | String.t(),
          title: nil | String.t(),
          updated: nil | String.t(),
          categories: [String.t()],
          image: nil | Rss.Basic.Attachment.t(),
          links: [Reed.Basic.Link.t()],
          items: [Reed.Basic.Item.t()],
          data: map()
        }

  def to_feed(data) when is_map(data) do
    {data, other_data} =
      data
      |> Map.delete("_reed_normalized_")
      |> Map.split([
        "authors",
        "id",
        "image",
        "language",
        "subtitle",
        "summary",
        "title",
        "updated",
        "categories",
        "links",
        "items"
      ])

    {image, data} = Map.pop(data, "image")
    {links, data} = Map.pop(data, "links", [])
    {items, data} = Map.pop(data, "items", [])
    image = Reed.Basic.Attachment.to_attachment(image)
    links = Enum.map(links, &Reed.Basic.Link.to_link/1)
    items = Enum.map(items, &Reed.Basic.Item.to_item/1)
    feed_url = Reed.Basic.Link.url(links, "self")
    id = Map.get(data, "id")

    data =
      if is_nil(id) && !is_nil(feed_url) do
        Logger.info("Basic.Feed using self link #{feed_url} for feed id")
        Map.put(data, "id", feed_url)
      else
        data
      end

    data =
      data
      |> AtomicMap.convert(safe: true)
      |> Map.merge(%{image: image, links: links, items: items, data: other_data})

    struct(__MODULE__, data)
  end

  def self_url(%__MODULE__{links: links}) do
    Reed.Basic.Link.url(links, "self")
  end

  def site_url(%__MODULE__{links: links}) do
    Reed.Basic.Link.url(links, "alternate")
  end

  def host(%__MODULE__{} = feed) do
    feed |> site_url() |> parse_host()
  end

  def parse_host(url) do
    uri = URI.parse(url)
    uri.host
  end
end
