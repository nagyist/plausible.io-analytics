defmodule Plausible.TestUtils do
  use Plausible.Repo
  use Plausible
  alias Plausible.Factory

  defmacro __using__(_) do
    quote do
      require Plausible.TestUtils
      import Plausible.TestUtils
    end
  end

  defmacro patch_env(env_key, value) do
    quote do
      if __MODULE__.__info__(:attributes)[:ex_unit_async] == [true] do
        raise "Patching env is unsafe in asynchronous tests. maybe extract the case elsewhere?"
      end

      original_env = Application.get_env(:plausible, unquote(env_key))
      Application.put_env(:plausible, unquote(env_key), unquote(value))

      on_exit(fn ->
        Application.put_env(:plausible, unquote(env_key), original_env)
      end)

      {:ok, %{patched_env: true}}
    end
  end

  defmacro setup_patch_env(env_key, value) do
    quote do
      setup do
        patch_env(unquote(env_key), unquote(value))
      end
    end
  end

  def setup_do(context \\ %{}, step_fn) do
    case step_fn.(context) do
      {:ok, ctx} -> Map.merge(context, Map.new(ctx))
      ctx -> Map.merge(context, Map.new(ctx))
    end
  end

  def create_user(_) do
    {:ok, user: Plausible.Teams.Test.new_user()}
  end

  def create_site(%{user: user}) do
    {:ok, site: Plausible.Teams.Test.new_site(owner: user)}
  end

  def create_team(%{user: user}) do
    {:ok, team} = Plausible.Teams.get_or_create(user)
    {:ok, team: team}
  end

  def setup_team(%{conn: conn, team: team}) do
    team = Plausible.Teams.complete_setup(team)

    conn =
      conn
      |> Plug.Conn.fetch_session()
      |> Plug.Conn.put_session(:current_team_id, team.identifier)

    {:ok, conn: conn, team: team}
  end

  def create_legacy_site_import(%{site: site}) do
    create_site_import(%{site: site, create_legacy_import?: true})
  end

  def create_site_import(%{site: site} = opts) do
    site_import =
      Factory.insert(:site_import,
        site: site,
        start_date: ~D[2005-01-01],
        end_date: Timex.today(),
        source: :universal_analytics,
        legacy: opts[:create_legacy_import?] == true
      )

    {:ok, site_import: site_import}
  end

  def create_api_key(%{user: user}) do
    team = Plausible.Teams.Test.team_of(user)
    api_key = Factory.insert(:api_key, user: user, team: team)

    {:ok, api_key: api_key.key}
  end

  def use_api_key(%{conn: conn, api_key: api_key}) do
    conn = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{api_key}")

    {:ok, conn: conn}
  end

  def log_in(%{user: user, conn: conn}) do
    conn =
      conn
      |> init_session()
      |> PlausibleWeb.UserAuth.log_in_user(user)
      |> Phoenix.ConnTest.recycle()
      |> Map.put(:secret_key_base, secret_key_base())
      |> init_session()

    {:ok, conn: conn}
  end

  on_ee do
    alias Plausible.Auth.SSO

    def setup_sso(%{team: team} = ctx) do
      team = Plausible.Teams.complete_setup(team)
      integration = SSO.initiate_saml_integration(team)

      {:ok, sso_domain} = SSO.Domains.add(integration, ctx[:domain] || "example.com")
      _sso_domain = SSO.Domains.verify(sso_domain, skip_checks?: true)

      {:ok, team: team, sso_integration: integration, sso_domain: sso_domain}
    end

    def provision_sso_user(%{user: user, sso_integration: integration}) do
      identity = new_identity(user.name, user.email, integration)
      {:ok, _, _, sso_user} = SSO.provision_user(identity)

      {:ok, user: sso_user}
    end
  end

  def init_session(conn) do
    opts =
      Plug.Session.init(
        store: :cookie,
        key: "foobar",
        encryption_salt: "encrypted cookie salt",
        signing_salt: "signing salt",
        log: false,
        encrypt: false
      )

    conn
    |> Plug.Session.call(opts)
    |> Plug.Conn.fetch_session()
  end

  def generate_usage_for(site, i, timestamp \\ NaiveDateTime.utc_now()) do
    events = for _i <- 1..i, do: Factory.build(:pageview, timestamp: timestamp)
    populate_stats(site, events)
    :ok
  end

  def populate_stats(site, import_id, events) do
    Enum.map(events, fn event ->
      event = Map.put(event, :site_id, site.id)

      case event do
        %Plausible.ClickhouseEventV2{} ->
          event

        imported_event ->
          Map.put(imported_event, :import_id, import_id)
      end
    end)
    |> populate_stats
  end

  def populate_stats(site, events) do
    Enum.map(events, fn event ->
      Map.put(event, :site_id, site.id)
    end)
    |> populate_stats
  end

  def populate_stats(events) do
    {native, imported} =
      events
      |> Enum.map(fn event ->
        case event do
          %{timestamp: timestamp} ->
            %{event | timestamp: to_naive_truncate(timestamp)}

          _other ->
            event
        end
      end)
      |> Enum.split_with(fn event ->
        case event do
          %Plausible.ClickhouseEventV2{} ->
            true

          _ ->
            false
        end
      end)

    populate_native_stats(native)
    populate_imported_stats(imported)
  end

  defp populate_native_stats(events) do
    for event_params <- events do
      {:ok, session} =
        Plausible.Session.CacheStore.on_event(event_params, event_params, nil,
          skip_balancer?: true
        )

      event_params
      |> Plausible.ClickhouseEventV2.merge_session(session)
      |> Plausible.Event.WriteBuffer.insert()
    end

    Plausible.Session.WriteBuffer.flush()
    Plausible.Event.WriteBuffer.flush()
  end

  defp populate_imported_stats(events) do
    Enum.group_by(events, &Map.fetch!(&1, :table), &Map.delete(&1, :table))
    |> Enum.map(fn {table, events} -> Plausible.Imported.Buffer.insert_all(table, events) end)
  end

  def relative_time(shifts) do
    NaiveDateTime.utc_now()
    |> Timex.shift(shifts)
    |> NaiveDateTime.truncate(:second)
  end

  def to_naive_truncate(%DateTime{} = dt) do
    to_naive_truncate(DateTime.to_naive(dt))
  end

  def to_naive_truncate(%NaiveDateTime{} = naive) do
    NaiveDateTime.truncate(naive, :second)
  end

  def to_naive_truncate(%Date{} = date) do
    NaiveDateTime.new!(date, ~T[00:00:00])
  end

  def eventually(expectation, wait_time_ms \\ 50, retries \\ 10) do
    Enum.reduce_while(1..retries, nil, fn attempt, _acc ->
      case expectation.() do
        {true, result} ->
          {:halt, result}

        {false, _} ->
          Process.sleep(wait_time_ms * attempt)
          {:cont, nil}
      end
    end)
  end

  def await_clickhouse_count(query, expected) do
    eventually(
      fn ->
        count = Plausible.ClickhouseRepo.aggregate(query, :count)

        {count == expected, count}
      end,
      100,
      10
    )
  end

  def random_ip() do
    Enum.map_join(1..4, ".", fn _ -> Enum.random(1..254) end)
  end

  def minio_running? do
    %{host: host, port: port} = ExAws.Config.new(:s3)
    healthcheck_req = Finch.build(:head, "http://#{host}:#{port}")

    case Finch.request(healthcheck_req, Plausible.Finch) do
      {:ok, %Finch.Response{}} -> true
      {:error, %Mint.TransportError{reason: :econnrefused}} -> false
    end
  end

  def ensure_minio do
    unless minio_running?() do
      %{host: host, port: port} = ExAws.Config.new(:s3)

      IO.puts("""
      #{IO.ANSI.red()}
      You are trying to run MinIO tests (--include minio) \
      but nothing is running on #{"http://#{host}:#{port}"}.
      #{IO.ANSI.blue()}Please make sure to start MinIO with `make minio`#{IO.ANSI.reset()}
      """)

      :init.stop(1)
    end
  end

  if Mix.env() == :test do
    def maybe_fake_minio(_context) do
      unless minio_running?() do
        %{port: port} = ExAws.Config.new(:s3)
        bypass = Bypass.open(port: port)

        Bypass.expect(bypass, fn conn ->
          # we only need to fake HeadObject, all the other S3 requests are "controlled"
          "HEAD" = conn.method

          # we pretent the object is not found
          Plug.Conn.send_resp(conn, 404, [])
        end)
      end

      :ok
    end
  else
    def maybe_fake_minio(_context) do
      :ok
    end
  end

  def monthly_pageview_usage_stub(penultimate_usage, last_usage) do
    last_bill_date = Date.utc_today() |> Date.shift(day: -1)

    Plausible.Teams.Billing
    |> Double.stub(:monthly_pageview_usage, fn _user ->
      %{
        last_cycle: %{
          date_range:
            Date.range(
              Date.shift(last_bill_date, month: -1),
              Date.shift(last_bill_date, day: -1)
            ),
          total: last_usage
        },
        penultimate_cycle: %{
          date_range:
            Date.range(
              Date.shift(last_bill_date, month: -2),
              Date.shift(last_bill_date, day: -1, month: -1)
            ),
          total: penultimate_usage
        }
      }
    end)
  end

  defp secret_key_base() do
    :plausible
    |> Application.fetch_env!(PlausibleWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end

  # normal `@tag :tmp_dir` might not work in Plausible.Session.Transfer tests
  # if the path is too long for unix domain sockets (>104)
  # this one makes paths a bit shorter
  def tmp_dir do
    name = "plausible-#{System.unique_integer([:positive])}"
    tmp_dir = Path.join(System.tmp_dir!(), name)
    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(tmp_dir) end)
    tmp_dir
  end

  on_ee do
    def new_identity(name, email, integration, id \\ Ecto.UUID.generate()) do
      %Plausible.Auth.SSO.Identity{
        id: id,
        integration_id: integration.identifier,
        name: name,
        email: email,
        expires_at: NaiveDateTime.add(NaiveDateTime.utc_now(:second), 6, :hour)
      }
    end
  end
end
