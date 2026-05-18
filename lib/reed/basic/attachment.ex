defmodule Reed.Basic.Attachment do
  require Logger

  @derive Jason.Encoder
  defstruct [:url, :size, :height, :width, :type, :title, :link, :primary, :data]

  @type t :: %__MODULE__{
          url: String.t(),
          size: nil | integer(),
          height: nil | integer(),
          width: nil | integer(),
          type: nil | String.t(),
          title: nil | String.t(),
          link: nil | String.t(),
          primary: nil | boolean(),
          data: map()
        }

  def to_attachment(url) when is_binary(url) do
    struct(__MODULE__, maybe_add_mime_type(url))
  end

  def to_attachment(data) when is_map(data) do
    {data, other_data} =
      Map.split(data, ["url", "size", "height", "width", "type", "title", "link", "primary"])

    data =
      data
      |> AtomicMap.convert(safe: true)
      |> maybe_add_mime_type()
      |> Map.put(:data, other_data)

    struct(__MODULE__, data)
  end

  def to_attachment(_), do: nil

  defp maybe_add_mime_type(%{url: _url, type: _type} = attachment), do: attachment

  defp maybe_add_mime_type(%{url: url} = attachment) do
    case maybe_add_mime_type(url) do
      %{type: type} -> Map.put(attachment, :type, type)
      _ -> attachment
    end
  end

  defp maybe_add_mime_type(url) when is_binary(url) do
    type = url |> url_path() |> MIME.from_path()

    if type != "application/octet-stream" do
      %{url: url, type: type}
    else
      Logger.debug("no mime type for #{url}")
      %{url: url}
    end
  end

  defp url_path(url) do
    uri = URI.parse(url)
    uri.path
  end
end

defimpl String.Chars, for: Reed.Basic.Attachment do
  def to_string(attachment), do: attachment.url
end
