defmodule TowerDB.RequestData do
  @moduledoc false

  @allowed_headers ["user-agent", "content-type", "referer", "accept-language", "cookie"]

  @default_filtered_header_keys ~w(authorization cookie set-cookie x-api-key)

  @filtered_placeholder "[FILTERED]"

  @default_filtered_param_keys ~w(
    password password_confirmation token secret api_key
    authorization credit_card cvv
  )

  def build(%Plug.Conn{} = conn) do
    %{
      "url" => url(conn),
      "method" => conn.method,
      "user_ip" => user_ip(conn),
      "headers" => headers(conn),
      "params" => params(conn)
    }
  end

  defp url(conn) do
    "#{conn.scheme}://#{conn.host}:#{conn.port}#{conn.request_path}"
  end

  defp user_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> List.to_string()
  end

  defp headers(conn) do
    conn.req_headers
    |> Enum.filter(fn {name, _value} -> name in @allowed_headers end)
    |> Enum.map(&filter_header/1)
    |> Enum.into(%{})
  end

  defp filter_header({name, value}) do
    if name in @default_filtered_header_keys do
      {name, @filtered_placeholder}
    else
      {name, value}
    end
  end

  defp params(%Plug.Conn{params: %Plug.Conn.Unfetched{aspect: :params}}), do: "unfetched"

  defp params(conn) do
    conn
    |> Plug.Conn.fetch_query_params()
    |> Map.fetch!(:params)
    |> filter_params()
  end

  defp filter_params(%{} = params) do
    Map.new(params, fn {key, value} ->
      if filtered_param_key?(key) do
        {key, @filtered_placeholder}
      else
        {key, filter_params(value)}
      end
    end)
  end

  defp filter_params(params) when is_list(params), do: Enum.map(params, &filter_params/1)
  defp filter_params(value), do: value

  defp filtered_param_key?(key) when is_binary(key) do
    downcased_key = String.downcase(key)
    Enum.any?(@default_filtered_param_keys, &String.contains?(downcased_key, &1))
  end

  defp filtered_param_key?(_key), do: false
end
