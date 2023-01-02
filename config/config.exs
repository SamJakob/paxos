defmodule ConsoleLogger do
  def format(level, message, {date, time}, metadata) do
    metadata_str = if Enum.any?(metadata) do
      result = "#{if Keyword.has_key?(metadata, :data), do: "| " <> inspect(Keyword.get(metadata, :data)) <> " ", else: ""}"

      if Keyword.has_key?(metadata, :mfa) and Keyword.has_key?(metadata, :file) and level == :error do
        mfa_string = format_mfa(Keyword.get(metadata, :mfa))
        file_and_mfa_string = Keyword.get(metadata, :file) <> ":" <> mfa_string

        result <> "| " <> file_and_mfa_string
      else
        result
      end
    else
      ""
    end

    date_str = Logger.Formatter.format_date(date)
    time_str = Logger.Formatter.format_time(time)
    level_str = String.pad_trailing(String.upcase("[" <> Atom.to_string(level) <> "]"), 9)

    process_str = if Keyword.has_key?(metadata, :registered_name) do
      if is_atom(Keyword.get(metadata, :registered_name)) do
        Atom.to_string(Keyword.get(metadata, :registered_name))
      else
        inspect(Keyword.get(metadata, :registered_name))
      end
    else
      pid = Keyword.get(metadata, :pid)

      if is_pid(pid) and
        node(pid) == node() and
        is_tuple(Process.info(pid, :registered_name)) and
        is_atom(elem(Process.info(pid, :registered_name), 1)) do
        Atom.to_string(elem(Process.info(pid, :registered_name), 1))
      else
        inspect(pid)
      end
    end

    "[#{date_str} #{time_str}] #{level_str} #{String.pad_trailing("[" <> process_str <> "]", 15)} | #{message} #{metadata_str}\n"
  rescue
    error ->
      IO.puts(:standard_error, error)
      "#{inspect {level, message, {date, time}, metadata}} (formatting failed)\n"
  end

  # Format the module, function, arity string.
  defp format_mfa(mfa) do
    "#{elem(mfa, 0)}.#{Atom.to_string(elem(mfa, 1))}/#{elem(mfa, 2)}"
  end
end

import Config

config :logger, :console,
  format: {ConsoleLogger, :format},
  metadata: [:mfa, :file, :registered_name, :pid, :data],
  colors: [enabled: true],
  level: :warn
