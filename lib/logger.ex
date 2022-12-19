defmodule Logger1 do

  def error(module_name, process_name, message) do
    IO.puts(:stderr, "[ERROR] [#{DateTime.to_string(DateTime.utc_now())}] [#{module_name}:#{process_name}] #{message}")
  end

end
