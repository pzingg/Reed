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

  def to_attachment(data, base_url \\ nil)

  def to_attachment(url, base_url) when is_binary(url) do
    %__MODULE__{url: url} |> with_absolute_url_and_mime_type(base_url)
  end

  def to_attachment(data, base_url) when is_map(data) do
    {data, other_data} =
      Map.split(data, ["url", "size", "height", "width", "type", "title", "link", "primary"])

    data =
      data
      |> AtomicMap.convert(safe: true)
      |> Map.put(:data, other_data)

    struct(__MODULE__, data) |> with_absolute_url_and_mime_type(base_url)
  end

  def to_attachment(_, _), do: nil

  defp with_absolute_url_and_mime_type(%__MODULE__{url: url, type: type} = attachment, base_url)
       when is_binary(type) do
    %{attachment | url: absolute_url(url, base_url)}
  end

  defp with_absolute_url_and_mime_type(%__MODULE__{url: url} = attachment, base_url) do
    type = url |> url_path() |> MIME.from_path()
    url = absolute_url(url, base_url)

    if type != "application/octet-stream" do
      %{attachment | url: url, type: type}
    else
      Logger.debug("no mime type for #{url}")
      %{attachment | url: url}
    end
  end

  defp absolute_url(url, base_url) when is_binary(url) and is_binary(base_url) do
    uri = URI.parse(url)

    if uri.scheme do
      url
    else
      URI.merge(base_url, uri) |> URI.to_string()
    end
  end

  defp absolute_url(url, _), do: url

  defp url_path(url) do
    uri = URI.parse(url)
    uri.path
  end
end

defimpl String.Chars, for: Reed.Basic.Attachment do
  def to_string(attachment), do: attachment.url
end
