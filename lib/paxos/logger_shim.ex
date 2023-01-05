defmodule Paxos.LoggerShim do
  @moduledoc """
  A very simple logger shim that just prints formatted messages for the specified
  log levels. This is not considered a production-ready logger and exists just to
  stub the log methods. Ordinarily, this is used to turn off all internal logging
  for the Paxos implementation.
  """

  @printableLogLevels true

  defp write_log(level, message, device \\ :stdio) do
    if not is_list(@printableLogLevels) or Enum.member?(@printableLogLevels, level) do
      timestamp = DateTime.to_iso8601(DateTime.now!("Etc/UTC"))
      IO.puts(device, "#{timestamp} | #{level} | #{message}")
    end
  end

  defp message_with_data(message, data), do: "#{message} | (#{inspect Keyword.get(data, :data)}})"

  def debug(message), do: write_log("DEBUG", message)
  def debug(message, data), do: debug(message_with_data(message, data))

  def info(message), do: write_log("INFO", message)
  def info(message, data), do: info(message_with_data(message, data))

  def notice(message), do: write_log("NOTICE", message)
  def notice(message, data), do: notice(message_with_data(message, data))

  def warn(message), do: write_log("WARNING", message, :standard_error)
  def warn(message, data), do: warn(message_with_data(message, data))

  def error(message), do: write_log("ERROR", message, :standard_error)
  def error(message, data), do: error(message_with_data(message, data))

end
