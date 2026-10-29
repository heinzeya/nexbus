defmodule Datahub.GTFS do
  @moduledoc """
  Loads a GTFS static feed (e.g. TransLink's `google_transit.zip`) into the
  `gtfs_*` tables.

  Every row is stamped with a `version` date, so several feeds can be stored
  side by side. Loading a version first deletes that version's rows, then
  fills each table with a Flow pipeline that parses rows in parallel and
  inserts them in batches. There is no wrapping transaction, so a load that
  fails part way leaves that version partially filled until it is re-run;
  other versions are untouched.

  example:
    Datahub.GTFS.load_gtfs_file()
    Datahub.GTFS.load_gtfs_file("https://gtfs-static.translink.ca/gtfs/google_transit.zip")
    Datahub.GTFS.load_gtfs_file("/Users/heinzeya/Downloads/google_transit.zip")
    Datahub.GTFS.load_gtfs_file("google_transit.zip", version: ~D[2026-10-16])
  """

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Core.Repo
  alias Core.GTFS.{Calendar, CalendarDate, Route, Stop, StopTime, Trip}
  alias NimbleCSV.RFC4180, as: CSV

  # Postgres allows at most 65_535 bind parameters per statement.
  @max_params 65_535

  @tables [
    {"stops.txt", Stop},
    {"routes.txt", Route},
    {"trips.txt", Trip},
    {"stop_times.txt", StopTime},
    {"calendar.txt", Calendar},
    {"calendar_dates.txt", CalendarDate}
  ]

  @doc """
  Downloads (when `source` is an http(s) URL) and unzips a GTFS feed, then
  stores it under a version date. `source` defaults to the `:gtfs_url`
  configured for `:datahub`; a local zip path is used as is.

  The version is the feed's publish date, so every publish is stored
  separately and never overwrites another. It is taken from the trailing
  date in `feed_info.txt`'s `feed_version` (TransLink: `26SEP_20261023` ->
  2026-10-23), falling back to the newest file date inside the zip.
  Loading the same publish again replaces only its own rows.

  Options:
    * `:version` - use this version date instead

  Returns `{:ok, %{version: date, tables: counts}}` with the number of rows
  loaded per file.
  """
  def load_gtfs_file(source \\ Application.fetch_env!(:datahub, :gtfs_url), opts \\ []) do
    tmp_dir = Path.join(System.tmp_dir!(), "gtfs-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    try do
      with {:ok, zip_path} <- download(source, tmp_dir),
           {:ok, dir} <- unzip(zip_path, tmp_dir),
           {:ok, version} <- fetch_version(zip_path, dir, opts) do
        Logger.info("Loading GTFS version #{version}")
        {:ok, %{version: version, tables: Map.new(@tables, &load_table(dir, version, &1))}}
      end
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp fetch_version(zip_path, dir, opts) do
    cond do
      version = opts[:version] -> {:ok, version}
      version = feed_version_date(dir) -> {:ok, version}
      version = zip_file_date(zip_path) -> {:ok, version}
      true -> {:error, :no_version_date}
    end
  end

  defp feed_version_date(dir) do
    feed_info = Path.join(dir, "feed_info.txt")

    with true <- File.exists?(feed_info),
         [header, record | _] <- feed_info |> File.read!() |> CSV.parse_string(skip_headers: false),
         info = header |> Enum.map(&normalize_header/1) |> Enum.zip(record) |> Map.new(),
         [_, yyyymmdd] <- Regex.run(~r/(\d{8})\s*$/, info["feed_version"] || "") do
      date(yyyymmdd)
    else
      _ -> nil
    end
  end

  defp zip_file_date(zip_path) do
    case :zip.list_dir(String.to_charlist(zip_path)) do
      {:ok, [_comment | entries]} ->
        entries
        |> Enum.map(fn {:zip_file, _name, info, _comment, _offset, _size} -> elem(info, 5) end)
        |> Enum.max(fn -> nil end)
        |> case do
          {date, _time} -> Date.from_erl!(date)
          nil -> nil
        end

      _ ->
        nil
    end
  end

  # Streams the zip to disk rather than holding it in memory.
  defp download("http" <> _ = url, tmp_dir) do
    zip_path = Path.join(tmp_dir, "gtfs.zip")
    Logger.info("Downloading GTFS feed from #{url}")

    case Req.get(url, into: File.stream!(zip_path), decode_body: false, receive_timeout: 120_000) do
      {:ok, %Req.Response{status: 200}} -> {:ok, zip_path}
      {:ok, %Req.Response{status: status}} -> {:error, {:download_failed, status}}
      {:error, reason} -> {:error, {:download_failed, reason}}
    end
  end

  defp download(zip_path, _tmp_dir) do
    if File.exists?(zip_path), do: {:ok, zip_path}, else: {:error, {:file_not_found, zip_path}}
  end

  defp unzip(zip_path, tmp_dir) do
    file_list = Enum.map(["feed_info.txt" | Enum.map(@tables, &elem(&1, 0))], &String.to_charlist/1)

    case :zip.unzip(String.to_charlist(zip_path), cwd: String.to_charlist(tmp_dir), file_list: file_list) do
      {:ok, _files} -> {:ok, tmp_dir}
      {:error, reason} -> {:error, {:unzip_failed, reason}}
    end
  end

  defp load_table(dir, version, {file, schema}) do
    path = Path.join(dir, file)
    Repo.delete_all(from r in schema, where: r.version == ^version)

    count =
      if File.exists?(path) do
        stream_file_data_to_db(path, version, schema)
      else
        Logger.warning("GTFS feed has no #{file}; #{schema.__schema__(:source)} left empty")
        0
      end

    Logger.info("Loaded #{count} rows from #{file}")
    {file, count}
  end

  # Parses lines in parallel and inserts each window of rows as one batch.
  # Lines are parsed one at a time, so quoted fields spanning several lines
  # are not supported (GTFS feeds don't use them in practice).
  # Returns the number of rows inserted.
  defp stream_file_data_to_db(path, version, schema) do
    header = read_header(path)
    batch_size = div(@max_params, length(schema.__schema__(:fields)))

    path
    |> File.stream!(read_ahead: 100_000)
    |> Stream.drop(1)
    |> Flow.from_enumerable()
    |> Flow.flat_map(&CSV.parse_string(&1, skip_headers: false))
    |> Flow.map(fn record ->
      schema
      |> to_row(header |> Enum.zip(record) |> Map.new())
      |> Map.put(:version, version)
    end)
    |> Flow.partition(window: Flow.Window.count(batch_size))
    |> Flow.reduce(fn -> [] end, fn row, batch -> [row | batch] end)
    |> Flow.on_trigger(fn rows ->
      {inserted, _} = Repo.insert_all(schema, rows)
      {[inserted], []}
    end)
    |> Enum.sum()
  end

  defp read_header(path) do
    path
    |> File.stream!()
    |> Enum.take(1)
    |> Enum.join()
    |> CSV.parse_string(skip_headers: false)
    |> hd()
    |> Enum.map(&normalize_header/1)
  end

  defp normalize_header(name), do: name |> String.trim_leading("﻿") |> String.trim()

  defp to_row(Stop, r) do
    %{
      stop_id: r["stop_id"],
      stop_code: string(r["stop_code"]),
      stop_name: string(r["stop_name"]),
      latitude: float(r["stop_lat"]),
      longitude: float(r["stop_lon"]),
      location_type: integer(r["location_type"])
    }
  end

  defp to_row(Route, r) do
    %{
      route_id: r["route_id"],
      agency_id: string(r["agency_id"]),
      route_short_name: string(r["route_short_name"]),
      route_long_name: string(r["route_long_name"]),
      route_type: integer(r["route_type"]),
      route_color: string(r["route_color"]),
      route_text_color: string(r["route_text_color"])
    }
  end

  defp to_row(Trip, r) do
    %{
      trip_id: r["trip_id"],
      route_id: r["route_id"],
      service_id: r["service_id"],
      trip_headsign: string(r["trip_headsign"]),
      direction_id: integer(r["direction_id"]),
      block_id: string(r["block_id"]),
      shape_id: string(r["shape_id"])
    }
  end

  defp to_row(StopTime, r) do
    %{
      trip_id: r["trip_id"],
      stop_sequence: integer(r["stop_sequence"]),
      stop_id: r["stop_id"],
      arrival_time: seconds(r["arrival_time"]),
      departure_time: seconds(r["departure_time"]),
      stop_headsign: string(r["stop_headsign"]),
      pickup_type: integer(r["pickup_type"]),
      drop_off_type: integer(r["drop_off_type"])
    }
  end

  defp to_row(Calendar, r) do
    %{
      service_id: r["service_id"],
      monday: r["monday"] == "1",
      tuesday: r["tuesday"] == "1",
      wednesday: r["wednesday"] == "1",
      thursday: r["thursday"] == "1",
      friday: r["friday"] == "1",
      saturday: r["saturday"] == "1",
      sunday: r["sunday"] == "1",
      start_date: date(r["start_date"]),
      end_date: date(r["end_date"])
    }
  end

  defp to_row(CalendarDate, r) do
    %{
      service_id: r["service_id"],
      date: date(r["date"]),
      exception_type: integer(r["exception_type"])
    }
  end

  defp string(nil), do: nil
  defp string(value), do: if(String.trim(value) == "", do: nil, else: value)

  defp integer(value), do: with(v when is_binary(v) <- string(value), do: v |> String.trim() |> String.to_integer())

  defp float(value) do
    with v when is_binary(v) <- string(value) do
      {float, _rest} = v |> String.trim() |> Float.parse()
      float
    end
  end

  # "20261028" -> ~D[2026-10-28]
  defp date(<<y::binary-4, m::binary-2, d::binary-2>>),
    do: Date.new!(String.to_integer(y), String.to_integer(m), String.to_integer(d))

  # " 5:05:00" / "25:10:00" -> seconds after midnight of the service day
  defp seconds(value) do
    with v when is_binary(v) <- string(value) do
      [h, m, s] = v |> String.trim() |> String.split(":") |> Enum.map(&String.to_integer/1)
      h * 3600 + m * 60 + s
    end
  end
end
