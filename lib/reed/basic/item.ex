defmodule Reed.Basic.Item do
  @derive Jason.Encoder
  defstruct authors: nil,
            content: nil,
            content_base: nil,
            duration: nil,
            id: nil,
            image: nil,
            language: nil,
            site_url: nil,
            subtitle: nil,
            summary: nil,
            title: nil,
            published: nil,
            updated: nil,
            permalink: "undefined",
            categories: [],
            links: [],
            attachments: [],
            data: %{}

  @type t :: %__MODULE__{
          authors: nil,
          content: nil | String.t(),
          content_base: nil | String.t(),
          duration: nil | integer(),
          id: nil | String.t(),
          image: nil | String.t(),
          language: nil | String.t(),
          site_url: nil | String.t(),
          subtitle: nil | String.t(),
          summary: nil | String.t(),
          title: nil | String.t(),
          published: nil | String.t(),
          updated: nil | String.t(),
          permalink: String.t(),
          categories: [String.t()],
          links: [Reed.Basic.Link.t()],
          attachments: [Reed.Basic.Attachment.t()],
          data: map()
        }

  def to_item(data) when is_map(data) do
    {data, other_data} =
      data
      |> Map.delete("_reed_normalized_")
      |> Map.split([
        "authors",
        "content",
        "content_base",
        "duration",
        "id",
        "permalink",
        "image",
        "language",
        "site_url",
        "subtitle",
        "summary",
        "title",
        "published",
        "updated",
        "categories",
        "links",
        "attachments"
      ])

    {links, data} = Map.pop(data, "links", [])
    {attachments, data} = Map.pop(data, "attachments", [])
    links = Enum.map(links, &Reed.Basic.Link.to_link/1)
    attachments = Enum.map(attachments, &Reed.Basic.Attachment.to_attachment/1)

    data =
      data
      |> AtomicMap.convert(safe: true)
      |> Map.merge(%{links: links, attachments: attachments, data: other_data})

    struct(__MODULE__, data)
  end

  def url(%__MODULE__{links: links}) do
    Reed.Basic.Link.url(links, ["self", "related", "alternate", "any"])
  end

  def content_base_url(%__MODULE__{content_base: base}) when is_binary(base), do: base
  def content_base_url(%__MODULE__{} = item), do: url(item)
end
