defmodule TowerDB.RequestDataTest do
  use ExUnit.Case, async: true

  alias TowerDB.RequestData

  describe "build/1" do
    test "extracts url without query string, method, and user_ip" do
      conn =
        Plug.Test.conn(:get, "/users/1?foo=bar")
        |> Map.put(:host, "example.com")
        |> Map.put(:port, 80)
        |> Map.put(:scheme, :http)
        |> Map.put(:remote_ip, {127, 0, 0, 1})

      request_data = RequestData.build(conn)

      assert request_data["url"] == "http://example.com:80/users/1"
      assert request_data["method"] == "GET"
      assert request_data["user_ip"] == "127.0.0.1"
    end

    test "returns fetched params merged from query and body" do
      conn =
        Plug.Test.conn(:get, "/users?foo=bar")
        |> Plug.Conn.fetch_query_params()

      request_data = RequestData.build(conn)

      assert request_data["params"] == %{"foo" => "bar"}
    end

    test "returns \"unfetched\" when params were never fetched" do
      conn = Plug.Test.conn(:get, "/users?foo=bar")

      request_data = RequestData.build(conn)

      assert request_data["params"] == "unfetched"
    end

    test "only includes allowlisted headers" do
      conn =
        Plug.Test.conn(:get, "/users")
        |> Plug.Conn.put_req_header("user-agent", "ExampleBrowser/1.0")
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("x-request-id", "req-123")

      request_data = RequestData.build(conn)

      assert request_data["headers"] == %{
               "user-agent" => "ExampleBrowser/1.0",
               "content-type" => "application/json"
             }
    end

    test "filters denylisted param keys, case-insensitively" do
      conn =
        Plug.Test.conn(:post, "/login", %{
          "email" => "user@example.com",
          "PASSWORD" => "hunter2",
          "token" => "abc123"
        })
        |> Plug.Conn.fetch_query_params()

      request_data = RequestData.build(conn)

      assert request_data["params"] == %{
               "email" => "user@example.com",
               "PASSWORD" => "[FILTERED]",
               "token" => "[FILTERED]"
             }
    end

    test "filters param keys that contain a denylisted substring" do
      conn =
        Plug.Test.conn(:post, "/users", %{
          "user_password" => "hunter2",
          "old_password" => "hunter1",
          "email" => "user@example.com"
        })
        |> Plug.Conn.fetch_query_params()

      request_data = RequestData.build(conn)

      assert request_data["params"] == %{
               "user_password" => "[FILTERED]",
               "old_password" => "[FILTERED]",
               "email" => "user@example.com"
             }
    end

    test "filters denylisted keys inside nested params" do
      conn =
        Plug.Test.conn(:post, "/users", %{
          "user" => %{"name" => "Jane", "password" => "hunter2"}
        })
        |> Plug.Conn.fetch_query_params()

      request_data = RequestData.build(conn)

      assert request_data["params"] == %{
               "user" => %{"name" => "Jane", "password" => "[FILTERED]"}
             }
    end

    test "filters denylisted headers within the allowlist" do
      conn =
        Plug.Test.conn(:get, "/users")
        |> Plug.Conn.put_req_header("user-agent", "ExampleBrowser/1.0")
        |> Plug.Conn.put_req_header("cookie", "session=abc123")

      request_data = RequestData.build(conn)

      assert request_data["headers"] == %{
               "user-agent" => "ExampleBrowser/1.0",
               "cookie" => "[FILTERED]"
             }
    end
  end
end
