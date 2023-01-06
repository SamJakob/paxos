# paxos.ex
# Generated on Jan. 05, 2023 at 10:52:44 PM

###########
# Type: Mix Dependency (typed_struct)
# deps/typed_struct/lib/typed_struct.ex
###########
defmodule TypedStruct do

  @accumulating_attrs [
    :ts_plugins,
    :ts_plugin_fields,
    :ts_fields,
    :ts_types,
    :ts_enforce_keys
  ]

  @attrs_to_delete [:ts_enforce? | @accumulating_attrs]

  @doc false
  defmacro __using__(_) do
    quote do
      import TypedStruct, only: [typedstruct: 1, typedstruct: 2]
    end
  end

  @doc """
  Defines a typed struct.

  Inside a `typedstruct` block, each field is defined through the `field/2`
  macro.

  ## Options

    * `enforce` - if set to true, sets `enforce: true` to all fields by default.
      This can be overridden by setting `enforce: false` or a default value on
      individual fields.
    * `opaque` - if set to true, creates an opaque type for the struct.
    * `module` - if set, creates the struct in a submodule named `module`.

  ## Examples

      defmodule MyStruct do
        use TypedStruct

        typedstruct do
          field :field_one, String.t()
          field :field_two, integer(), enforce: true
          field :field_three, boolean(), enforce: true
          field :field_four, atom(), default: :hey
        end
      end

  The following is an equivalent using the *enforce by default* behaviour:

      defmodule MyStruct do
        use TypedStruct

        typedstruct enforce: true do
          field :field_one, String.t(), enforce: false
          field :field_two, integer()
          field :field_three, boolean()
          field :field_four, atom(), default: :hey
        end
      end

  You can create the struct in a submodule instead:

      defmodule MyModule do
        use TypedStruct

        typedstruct module: Struct do
          field :field_one, String.t()
          field :field_two, integer(), enforce: true
          field :field_three, boolean(), enforce: true
          field :field_four, atom(), default: :hey
        end
      end
  """
  defmacro typedstruct(opts \\ [], do: block) do
    ast = TypedStruct.__typedstruct__(block, opts)

    case opts[:module] do
      nil ->
        quote do
          # Create a lexical scope.
          (fn -> unquote(ast) end).()
        end

      module ->
        quote do
          defmodule unquote(module) do
            unquote(ast)
          end
        end
    end
  end

  @doc false
  def __typedstruct__(block, opts) do
    quote do
      Enum.each(unquote(@accumulating_attrs), fn attr ->
        Module.register_attribute(__MODULE__, attr, accumulate: true)
      end)

      Module.put_attribute(__MODULE__, :ts_enforce?, unquote(!!opts[:enforce]))
      @before_compile {unquote(__MODULE__), :__plugin_callbacks__}

      import TypedStruct
      unquote(block)

      @enforce_keys @ts_enforce_keys
      defstruct @ts_fields

      TypedStruct.__type__(@ts_types, unquote(opts))
    end
  end

  @doc false
  defmacro __type__(types, opts) do
    if Keyword.get(opts, :opaque, false) do
      quote bind_quoted: [types: types] do
        @opaque t() :: %__MODULE__{unquote_splicing(types)}
      end
    else
      quote bind_quoted: [types: types] do
        @type t() :: %__MODULE__{unquote_splicing(types)}
      end
    end
  end

  @doc """
  Registers a plugin for the currently defined struct.

  ## Example

      typedstruct do
        plugin MyPlugin

        field :a_field, String.t()
      end

  For more information on how to define your own plugins, please see
  `TypedStruct.Plugin`. To use a third-party plugin, please refer directly to
  its documentation.
  """
  defmacro plugin(plugin, opts \\ []) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :ts_plugins,
        {unquote(plugin), unquote(opts)}
      )

      require unquote(plugin)
      unquote(plugin).init(unquote(opts))
    end
  end

  @doc """
  Defines a field in a typed struct.

  ## Example

      # A field named :example of type String.t()
      field :example, String.t()

  ## Options

    * `default` - sets the default value for the field
    * `enforce` - if set to true, enforces the field and makes its type
      non-nullable
  """
  defmacro field(name, type, opts \\ []) do
    quote bind_quoted: [name: name, type: Macro.escape(type), opts: opts] do
      TypedStruct.__field__(name, type, opts, __ENV__)
    end
  end

  @doc false
  def __field__(name, type, opts, %Macro.Env{module: mod} = env)
      when is_atom(name) do
    if mod |> Module.get_attribute(:ts_fields) |> Keyword.has_key?(name) do
      raise ArgumentError, "the field #{inspect(name)} is already set"
    end

    has_default? = Keyword.has_key?(opts, :default)
    enforce_by_default? = Module.get_attribute(mod, :ts_enforce?)

    enforce? =
      if is_nil(opts[:enforce]),
        do: enforce_by_default? && !has_default?,
        else: !!opts[:enforce]

    nullable? = !has_default? && !enforce?

    Module.put_attribute(mod, :ts_fields, {name, opts[:default]})
    Module.put_attribute(mod, :ts_plugin_fields, {name, type, opts, env})
    Module.put_attribute(mod, :ts_types, {name, type_for(type, nullable?)})
    if enforce?, do: Module.put_attribute(mod, :ts_enforce_keys, name)
  end

  def __field__(name, _type, _opts, _env) do
    raise ArgumentError, "a field name must be an atom, got #{inspect(name)}"
  end

  # Makes the type nullable if the key is not enforced.
  defp type_for(type, false), do: type
  defp type_for(type, _), do: quote(do: unquote(type) | nil)

  @doc false
  defmacro __plugin_callbacks__(%Macro.Env{module: module}) do
    plugins = Module.get_attribute(module, :ts_plugins)
    fields = Module.get_attribute(module, :ts_plugin_fields) |> Enum.reverse()

    Enum.each(unquote(@attrs_to_delete), &Module.delete_attribute(module, &1))

    fields_block =
      for {plugin, plugin_opts} <- plugins,
          {name, type, field_opts, env} <- fields do
        plugin.field(name, type, field_opts ++ plugin_opts, env)
      end

    after_definition_block =
      for {plugin, plugin_opts} <- plugins do
        plugin.after_definition(plugin_opts)
      end

    quote do
      unquote_splicing(fields_block)
      unquote_splicing(after_definition_block)
    end
  end
end


###########
# Type: Mix Dependency (typed_struct)
# deps/typed_struct/lib/typed_struct/plugin.ex
###########
defmodule TypedStruct.Plugin do
  @moduledoc """
  This module defines the plugin interface for TypedStruct.

  ## Rationale

  Sometimes you may want to define helpers on your structs, for all their fields
  or for the struct as a whole. This plugin interface lets you integrate your
  own needs with TypedStruct.

  ## Plugin definition

  A TypedStruct plugin is a module that implements `TypedStruct.Plugin`. Three
  callbacks are available to you for injecting code at different steps:

    * `c:init/1` lets you inject code where the `TypedStruct.plugin/2` macro is
      called,
    * `c:field/4` lets you inject code on each field definition,
    * `c:after_definition/1` lets you insert code after the struct and its type
      have been defined.

  `use`-ing this module will inject default implementations of all
  three, so you only have to implement those you care about.

  ### Example

  As an example, let’s define a plugin that allows users to add an optional
  description to their structs and fields. This plugin also takes an `upcase`
  option. If set to `true`, all the descriptions are then upcased. It would be
  used this way:

      defmodule MyStruct do
        use TypedStruct

        typedstruct do
          # We import the plugin with the upcase option set to `true`.
          plugin DescribedStruct, upcase: true

          # We can now set a description for the struct.
          description "My struct"

          # We can also set a description on a field.
          field :a_field, String.t(), description: "A field"
          field :second_field, boolean()
        end
      end

  Once compiled, we would optain:

      iex> MyStruct.struct_description()
      "MY STRUCT"
      iex> MyStruct.field_description(:a_field)
      "A FIELD"

  Follows the plugin definition:

      defmodule DescribedStruct do
        use TypedStruct.Plugin

        # The init macro lets you inject code where the plugin macro is called.
        # You can think a bit of it like a `use` but for the scope of the
        # typedstruct block.
        @impl true
        @spec init(keyword()) :: Macro.t()
        defmacro init(opts) do
          quote do
            # Let’s import our custom `description` macro defined below so our
            # users can use it when defining their structs.
            import TypedStructDemoPlugin, only: [description: 1]

            # Let’s also store the upcase option in an attribute so we can
            # access it from the code injected by our `description/1` macro.
            @upcase unquote(opts)[:upcase]
          end
        end

        # This is a public macro our users can call in their typedstruct blocks.
        @spec description(String.t()) :: Macro.t()
        defmacro description(description) do
          quote do
            # Here we simply evaluate the result of __description__/2. We need
            # this indirection to be able to use @upcase after is has been
            # evaluated, but still in the code generation process. This way, we
            # can upcase the strings *at build time* if needed. It’s just a tiny
            # refinement :-)
            Module.eval_quoted(
              __MODULE__,
              TypedStructDemoPlugin.__description__(__MODULE__, unquote(description))
            )
          end
        end

        @spec __description__(module(), String.t()) :: Macro.t()
        def __description__(module, description) do
          # Maybe upcase the description at build time.
          description =
            module
            |> Module.get_attribute(:upcase)
            |> maybe_upcase(description)

          quote do
            # Let’s just generate a constant function that returns the
            # description.
            def struct_description, do: unquote(description)
          end
        end

        # The field callback is called for each field defined in the typedstruct
        # block. You get exactly what the user has passed to the field macro,
        # plus options from every plugin init. The `env` variable contains the
        # environment as it stood at the moment of the corresponding
        # `TypedStruct.field/3` call.
        @impl true
        @spec field(atom(), any(), keyword(), Macro.Env.t()) :: Macro.t()
        def field(name, _type, opts, _env) do
          # Same as for the struct description, we want to upcase at build time
          # if necessary. As we do not have access to the module here, we cannot
          # access @upcase. This is not an issue since the option is
          # automatically added to `opts`, in addition to the options passed to
          # the field macro.
          description = maybe_upcase(opts[:upcase], opts[:description] || "")

          quote do
            # We define a clause matching the field name returning its optional
            # description.
            def field_description(unquote(name)), do: unquote(description)
          end
        end

        defp maybe_upcase(true, description), do: String.upcase(description)
        defp maybe_upcase(_, description), do: description

        # The after_definition callback is called after the struct and its type
        # have been defined, at the end of the `typedstruct` block.
        @impl true
        @spec after_definition(opts :: keyword()) :: Macro.t()
        def after_definition(_opts) do
          quote do
            # Here we just clean the @upcase attribute so that it does not
            # pollute our user’s modules.
            Module.delete_attribute(__MODULE__, :upcase)
          end
        end
      end
  """

  @doc """
  Injects code where `TypedStruct.plugin/2` is called.
  """
  @macrocallback init(opts :: keyword()) :: Macro.t()

  @doc deprecated: "Use TypedStruct.Plugin.field/4 instead"
  @callback field(name :: atom(), type :: any(), opts :: keyword()) ::
              Macro.t()

  @doc """
  Injects code after each field definition.

  `name` and `type` are the exact values passed to the `TypedStruct.field/3`
  macro in the `typedstruct` block. `opts` is the concatenation of the options
  passed to the `field` macro and those from the plugin init. `env` is the
  environment at the time of each field definition.
  """
  @callback field(
              name :: atom(),
              type :: any(),
              opts :: keyword(),
              env :: Macro.Env.t()
            ) ::
              Macro.t()

  @doc """
  Injects code after the struct and its type have been defined.
  """
  @callback after_definition(opts :: keyword()) :: Macro.t()

  @optional_callbacks [field: 3, field: 4]

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour TypedStruct.Plugin
      @before_compile {unquote(__MODULE__), :maybe_define_field_4}

      @doc false
      defmacro init(_opts), do: nil

      @doc false
      def after_definition(_opts), do: nil

      defoverridable init: 1, after_definition: 1
    end
  end

  @doc false
  defmacro maybe_define_field_4(env) do
    case {Module.defines?(env.module, {:field, 3}, :def),
          Module.defines?(env.module, {:field, 4}, :def)} do
      {false, false} ->
        # If none is present, let’s define a default implementation for field/4.
        quote do
          @doc false
          def field(_name, _type, _opts, _env), do: nil
        end

      {false, true} ->
        # If field/4 is present, allright.
        nil

      {true, false} ->
        # If field/3 is present, let’s define field/4 from it for compatibility.
        IO.warn([
          Atom.to_string(env.module),
          " defines field/3, which is deprecated. Please use field/4 instead"
        ])

        quote do
          @doc false
          def field(name, type, opts, _env) do
            field(name, type, opts)
          end
        end

      {true, true} ->
        # If both are present, this is an issue.
        IO.warn([
          Atom.to_string(env.module),
          " defines both field/3 and field/4 callbacks.",
          " Only field/4 will be invoked"
        ])
    end
  end
end


###########
# Type: Mix Dependency (uuid)
# deps/uuid/lib/uuid.ex
###########
defmodule UUID do
  use Bitwise, only_operators: true
  @moduledoc """
  UUID generator and utilities for [Elixir](http://elixir-lang.org/).
  See [RFC 4122](http://www.ietf.org/rfc/rfc4122.txt).
  """

  @nanosec_intervals_offset 122_192_928_000_000_000 # 15 Oct 1582 to 1 Jan 1970.
  @nanosec_intervals_factor 10 # Microseconds to nanoseconds factor.

  @variant10 2 # Variant, corresponds to variant 1 0 of RFC 4122.
  @uuid_v1 1 # UUID v1 identifier.
  @uuid_v3 3 # UUID v3 identifier.
  @uuid_v4 4 # UUID v4 identifier.
  @uuid_v5 5 # UUID v5 identifier.

  @urn "urn:uuid:" # UUID URN prefix.

  @doc """
  Inspect a UUID and return tuple with `{:ok, result}`, where result is
  information about its 128-bit binary content, type,
  version and variant.

  Timestamp portion is not checked to see if it's in the future, and therefore
  not yet assignable. See "Validation mechanism" in section 3 of
  [RFC 4122](http://www.ietf.org/rfc/rfc4122.txt).

  Will return `{:error, message}` if the given string is not a UUID representation
  in a format like:
  * `"870df8e8-3107-4487-8316-81e089b8c2cf"`
  * `"8ea1513df8a14dea9bea6b8f4b5b6e73"`
  * `"urn:uuid:ef1b1a28-ee34-11e3-8813-14109ff1a304"`

  ## Examples

  ```elixir
  iex> UUID.info("870df8e8-3107-4487-8316-81e089b8c2cf")
  {:ok, [uuid: "870df8e8-3107-4487-8316-81e089b8c2cf",
   binary: <<135, 13, 248, 232, 49, 7, 68, 135, 131, 22, 129, 224, 137, 184, 194, 207>>,
   type: :default,
   version: 4,
   variant: :rfc4122]}

  iex> UUID.info("8ea1513df8a14dea9bea6b8f4b5b6e73")
  {:ok, [uuid: "8ea1513df8a14dea9bea6b8f4b5b6e73",
   binary: <<142, 161, 81, 61, 248, 161, 77, 234, 155,
              234, 107, 143, 75, 91, 110, 115>>,
   type: :hex,
   version: 4,
   variant: :rfc4122]}

  iex> UUID.info("urn:uuid:ef1b1a28-ee34-11e3-8813-14109ff1a304")
  {:ok, [uuid: "urn:uuid:ef1b1a28-ee34-11e3-8813-14109ff1a304",
   binary: <<239, 27, 26, 40, 238, 52, 17, 227, 136, 19, 20, 16, 159, 241, 163, 4>>,
   type: :urn,
   version: 1,
   variant: :rfc4122]}

  iex> UUID.info("12345")
  {:error, "Invalid argument; Not a valid UUID: 12345"}

  ```

  """
  def info(uuid) do
    try do
      {:ok, UUID.info!(uuid)}
    rescue
      e in ArgumentError -> {:error, e.message}
    end
  end

  @doc """
  Inspect a UUID and return information about its 128-bit binary content, type,
  version and variant.

  Timestamp portion is not checked to see if it's in the future, and therefore
  not yet assignable. See "Validation mechanism" in section 3 of
  [RFC 4122](http://www.ietf.org/rfc/rfc4122.txt).

  Will raise an `ArgumentError` if the given string is not a UUID representation
  in a format like:
  * `"870df8e8-3107-4487-8316-81e089b8c2cf"`
  * `"8ea1513df8a14dea9bea6b8f4b5b6e73"`
  * `"urn:uuid:ef1b1a28-ee34-11e3-8813-14109ff1a304"`

  ## Examples

  ```elixir
  iex> UUID.info!("870df8e8-3107-4487-8316-81e089b8c2cf")
  [uuid: "870df8e8-3107-4487-8316-81e089b8c2cf",
   binary: <<135, 13, 248, 232, 49, 7, 68, 135, 131, 22, 129, 224, 137, 184, 194, 207>>,
   type: :default,
   version: 4,
   variant: :rfc4122]

  iex> UUID.info!("8ea1513df8a14dea9bea6b8f4b5b6e73")
  [uuid: "8ea1513df8a14dea9bea6b8f4b5b6e73",
   binary: <<142, 161, 81, 61, 248, 161, 77, 234, 155,
              234, 107, 143, 75, 91, 110, 115>>,
   type: :hex,
   version: 4,
   variant: :rfc4122]

  iex> UUID.info!("urn:uuid:ef1b1a28-ee34-11e3-8813-14109ff1a304")
  [uuid: "urn:uuid:ef1b1a28-ee34-11e3-8813-14109ff1a304",
   binary: <<239, 27, 26, 40, 238, 52, 17, 227, 136, 19, 20, 16, 159, 241, 163, 4>>,
   type: :urn,
   version: 1,
   variant: :rfc4122]

  ```

  """
  def info!(<<uuid::binary>> = uuid_string) do
    {type, <<uuid::128>>} = uuid_string_to_hex_pair(uuid)
    <<_::48, version::4, _::12, v0::1, v1::1, v2::1, _::61>> = <<uuid::128>>
    [uuid: uuid_string,
     binary: <<uuid::128>>,
     type: type,
     version: version,
     variant: variant(<<v0, v1, v2>>)]
  end
  def info!(_) do
    raise ArgumentError, message: "Invalid argument; Expected: String"
  end

  @doc """
  Convert binary UUID data to a string.

  Will raise an ArgumentError if the given binary is not valid UUID data, or
  the format argument is not one of: `:default`, `:hex`, or `:urn`.

  ## Examples

  ```elixir
  iex> UUID.binary_to_string!(<<135, 13, 248, 232, 49, 7, 68, 135,
  ...>        131, 22, 129, 224, 137, 184, 194, 207>>)
  "870df8e8-3107-4487-8316-81e089b8c2cf"

  iex> UUID.binary_to_string!(<<142, 161, 81, 61, 248, 161, 77, 234, 155,
  ...>        234, 107, 143, 75, 91, 110, 115>>, :hex)
  "8ea1513df8a14dea9bea6b8f4b5b6e73"

  iex> UUID.binary_to_string!(<<239, 27, 26, 40, 238, 52, 17, 227, 136,
  ...>        19, 20, 16, 159, 241, 163, 4>>, :urn)
  "urn:uuid:ef1b1a28-ee34-11e3-8813-14109ff1a304"

  ```

  """
  def binary_to_string!(uuid, format \\ :default)
  def binary_to_string!(<<uuid::binary>>, format) do
    uuid_to_string(<<uuid::binary>>, format)
  end
  def binary_to_string!(_, _) do
    raise ArgumentError, message: "Invalid argument; Expected: <<uuid::128>>"
  end

  @doc """
  Convert a UUID string to its binary data equivalent.

  Will raise an ArgumentError if the given string is not a UUID representation
  in a format like:
  * `"870df8e8-3107-4487-8316-81e089b8c2cf"`
  * `"8ea1513df8a14dea9bea6b8f4b5b6e73"`
  * `"urn:uuid:ef1b1a28-ee34-11e3-8813-14109ff1a304"`

  ## Examples

  ```elixir
  iex> UUID.string_to_binary!("870df8e8-3107-4487-8316-81e089b8c2cf")
  <<135, 13, 248, 232, 49, 7, 68, 135, 131, 22, 129, 224, 137, 184, 194, 207>>

  iex> UUID.string_to_binary!("8ea1513df8a14dea9bea6b8f4b5b6e73")
  <<142, 161, 81, 61, 248, 161, 77, 234, 155, 234, 107, 143, 75, 91, 110, 115>>

  iex> UUID.string_to_binary!("urn:uuid:ef1b1a28-ee34-11e3-8813-14109ff1a304")
  <<239, 27, 26, 40, 238, 52, 17, 227, 136, 19, 20, 16, 159, 241, 163, 4>>

  ```

  """
  def string_to_binary!(<<uuid::binary>>) do
    {_type, <<uuid::128>>} = uuid_string_to_hex_pair(uuid)
    <<uuid::128>>
  end
  def string_to_binary!(_) do
    raise ArgumentError, message: "Invalid argument; Expected: String"
  end

  @doc """
  Generate a new UUID v1. This version uses a combination of one or more of:
  unix epoch, random bytes, pid hash, and hardware address.

  ## Examples

  ```elixir
  iex> UUID.uuid1()
  "cdfdaf44-ee35-11e3-846b-14109ff1a304"

  iex> UUID.uuid1(:default)
  "cdfdaf44-ee35-11e3-846b-14109ff1a304"

  iex> UUID.uuid1(:hex)
  "cdfdaf44ee3511e3846b14109ff1a304"

  iex> UUID.uuid1(:urn)
  "urn:uuid:cdfdaf44-ee35-11e3-846b-14109ff1a304"

  ```

  """
  def uuid1(format \\ :default) do
    uuid1(uuid1_clockseq(), uuid1_node(), format)
  end

  @doc """
  Generate a new UUID v1, with an existing clock sequence and node address. This
  version uses a combination of one or more of: unix epoch, random bytes,
  pid hash, and hardware address.

  ## Examples

  ```elixir
  iex> UUID.uuid1()
  "cdfdaf44-ee35-11e3-846b-14109ff1a304"

  iex> UUID.uuid1(:default)
  "cdfdaf44-ee35-11e3-846b-14109ff1a304"

  iex> UUID.uuid1(:hex)
  "cdfdaf44ee3511e3846b14109ff1a304"

  iex> UUID.uuid1(:urn)
  "urn:uuid:cdfdaf44-ee35-11e3-846b-14109ff1a304"

  ```

  """
  def uuid1(clock_seq, node, format \\ :default)
  def uuid1(<<clock_seq::14>>, <<node::48>>, format) do
    <<time_hi::12, time_mid::16, time_low::32>> = uuid1_time()
    <<clock_seq_hi::6, clock_seq_low::8>> = <<clock_seq::14>>
    <<time_low::32, time_mid::16, @uuid_v1::4, time_hi::12, @variant10::2,
      clock_seq_hi::6, clock_seq_low::8, node::48>>
      |> uuid_to_string(format)
  end
  def uuid1(_, _, _) do
    raise ArgumentError, message:
    "Invalid argument; Expected: <<clock_seq::14>>, <<node::48>>"
  end

  @doc """
  Generate a new UUID v3. This version uses an MD5 hash of fixed value (chosen
  based on a namespace atom - see Appendix C of
  [RFC 4122](http://www.ietf.org/rfc/rfc4122.txt) and a name value. Can also be
  given an existing UUID String instead of a namespace atom.

  Accepted arguments are: `:dns`|`:url`|`:oid`|`:x500`|`:nil` OR uuid, String

  ## Examples

  ```elixir
  iex> UUID.uuid3(:dns, "my.domain.com")
  "03bf0706-b7e9-33b8-aee5-c6142a816478"

  iex> UUID.uuid3(:dns, "my.domain.com", :default)
  "03bf0706-b7e9-33b8-aee5-c6142a816478"

  iex> UUID.uuid3(:dns, "my.domain.com", :hex)
  "03bf0706b7e933b8aee5c6142a816478"

  iex> UUID.uuid3(:dns, "my.domain.com", :urn)
  "urn:uuid:03bf0706-b7e9-33b8-aee5-c6142a816478"

  iex> UUID.uuid3("cdfdaf44-ee35-11e3-846b-14109ff1a304", "my.domain.com")
  "8808f33a-3e11-3708-919e-15fba88908db"

  ```

  """
  def uuid3(namespace_or_uuid, name, format \\ :default)
  def uuid3(:dns, <<name::binary>>, format) do
    namebased_uuid(:md5, <<0x6ba7b8109dad11d180b400c04fd430c8::128, name::binary>>)
      |> uuid_to_string(format)
  end
  def uuid3(:url, <<name::binary>>, format) do
    namebased_uuid(:md5, <<0x6ba7b8119dad11d180b400c04fd430c8::128, name::binary>>)
      |> uuid_to_string(format)
  end
  def uuid3(:oid, <<name::binary>>, format) do
    namebased_uuid(:md5, <<0x6ba7b8129dad11d180b400c04fd430c8::128, name::binary>>)
      |> uuid_to_string(format)
  end
  def uuid3(:x500, <<name::binary>>, format) do
    namebased_uuid(:md5, <<0x6ba7b8149dad11d180b400c04fd430c8::128, name::binary>>)
      |> uuid_to_string(format)
  end
  def uuid3(:nil, <<name::binary>>, format) do
    namebased_uuid(:md5, <<0::128, name::binary>>)
      |> uuid_to_string(format)
  end
  def uuid3(<<uuid::binary>>, <<name::binary>>, format) do
    {_type, <<uuid::128>>} = uuid_string_to_hex_pair(uuid)
    namebased_uuid(:md5, <<uuid::128, name::binary>>)
      |> uuid_to_string(format)
  end
  def uuid3(_, _, _) do
    raise ArgumentError, message:
    "Invalid argument; Expected: :dns|:url|:oid|:x500|:nil OR String, String"
  end

  @doc """
  Generate a new UUID v4. This version uses pseudo-random bytes generated by
  the `crypto` module.

  ## Examples

  ```elixir
  iex> UUID.uuid4()
  "fb49a0ec-d60c-4d20-9264-3b4cfe272106"

  iex> UUID.uuid4(:default)
  "fb49a0ec-d60c-4d20-9264-3b4cfe272106"

  iex> UUID.uuid4(:hex)
  "fb49a0ecd60c4d2092643b4cfe272106"

  iex> UUID.uuid4(:urn)
  "urn:uuid:fb49a0ec-d60c-4d20-9264-3b4cfe272106"
  ```

  """
  def uuid4(), do: uuid4(:default)

  def uuid4(:strong), do: uuid4(:default) # For backwards compatibility.
  def uuid4(:weak),   do: uuid4(:default) # For backwards compatibility.
  def uuid4(format) do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)
    <<u0::48, @uuid_v4::4, u1::12, @variant10::2, u2::62>>
      |> uuid_to_string(format)
  end

  @doc """
  Generate a new UUID v5. This version uses an SHA1 hash of fixed value (chosen
  based on a namespace atom - see Appendix C of
  [RFC 4122](http://www.ietf.org/rfc/rfc4122.txt) and a name value. Can also be
  given an existing UUID String instead of a namespace atom.

  Accepted arguments are: `:dns`|`:url`|`:oid`|`:x500`|`:nil` OR uuid, String

  ## Examples

  ```elixir
  iex> UUID.uuid5(:dns, "my.domain.com")
  "016c25fd-70e0-56fe-9d1a-56e80fa20b82"

  iex> UUID.uuid5(:dns, "my.domain.com", :default)
  "016c25fd-70e0-56fe-9d1a-56e80fa20b82"

  iex> UUID.uuid5(:dns, "my.domain.com", :hex)
  "016c25fd70e056fe9d1a56e80fa20b82"

  iex> UUID.uuid5(:dns, "my.domain.com", :urn)
  "urn:uuid:016c25fd-70e0-56fe-9d1a-56e80fa20b82"

  iex> UUID.uuid5("fb49a0ec-d60c-4d20-9264-3b4cfe272106", "my.domain.com")
  "822cab19-df58-5eb4-98b5-c96c15c76d32"

  ```

  """
  def uuid5(namespace_or_uuid, name, format \\ :default)
  def uuid5(:dns, <<name::binary>>, format) do
    namebased_uuid(:sha1, <<0x6ba7b8109dad11d180b400c04fd430c8::128, name::binary>>)
      |> uuid_to_string(format)
  end
  def uuid5(:url, <<name::binary>>, format) do
    namebased_uuid(:sha1, <<0x6ba7b8119dad11d180b400c04fd430c8::128, name::binary>>)
      |> uuid_to_string(format)
  end
  def uuid5(:oid, <<name::binary>>, format) do
    namebased_uuid(:sha1, <<0x6ba7b8129dad11d180b400c04fd430c8::128, name::binary>>)
      |> uuid_to_string(format)
  end
  def uuid5(:x500, <<name::binary>>, format) do
    namebased_uuid(:sha1, <<0x6ba7b8149dad11d180b400c04fd430c8::128, name::binary>>)
      |> uuid_to_string(format)
  end
  def uuid5(:nil, <<name::binary>>, format) do
    namebased_uuid(:sha1, <<0::128, name::binary>>)
      |> uuid_to_string(format)
  end
  def uuid5(<<uuid::binary>>, <<name::binary>>, format) do
    {_type, <<uuid::128>>} = uuid_string_to_hex_pair(uuid)
    namebased_uuid(:sha1, <<uuid::128, name::binary>>)
      |> uuid_to_string(format)
  end
  def uuid5(_, _, _) do
    raise ArgumentError, message:
    "Invalid argument; Expected: :dns|:url|:oid|:x500|:nil OR String, String"
  end

  #
  # Internal utility functions.
  #

  # Convert UUID bytes to String.
  defp uuid_to_string(<<u0::32, u1::16, u2::16, u3::16, u4::48>>, :default) do
    [binary_to_hex_list(<<u0::32>>), ?-, binary_to_hex_list(<<u1::16>>), ?-,
     binary_to_hex_list(<<u2::16>>), ?-, binary_to_hex_list(<<u3::16>>), ?-,
     binary_to_hex_list(<<u4::48>>)]
      |> IO.iodata_to_binary
  end
  defp uuid_to_string(<<u::128>>, :hex) do
    binary_to_hex_list(<<u::128>>)
      |> IO.iodata_to_binary
  end
  defp uuid_to_string(<<u::128>>, :urn) do
    @urn <> uuid_to_string(<<u::128>>, :default)
  end
  defp uuid_to_string(_u, format) when format in [:default, :hex, :urn] do
    raise ArgumentError, message:
    "Invalid binary data; Expected: <<uuid::128>>"
  end
  defp uuid_to_string(_u, format) do
    raise ArgumentError, message:
    "Invalid format #{format}; Expected: :default|:hex|:urn"
  end

  # Extract the type (:default etc) and pure byte value from a UUID String.
  defp uuid_string_to_hex_pair(<<uuid::binary>>) do
    uuid = String.downcase(uuid)
    {type, hex_str} = case uuid do
      <<u0::64, ?-, u1::32, ?-, u2::32, ?-, u3::32, ?-, u4::96>> ->
        {:default, <<u0::64, u1::32, u2::32, u3::32, u4::96>>}
      <<u::256>> ->
        {:hex, <<u::256>>}
      <<@urn, u0::64, ?-, u1::32, ?-, u2::32, ?-, u3::32, ?-, u4::96>> ->
        {:urn, <<u0::64, u1::32, u2::32, u3::32, u4::96>>}
      _ ->
        raise ArgumentError, message:
          "Invalid argument; Not a valid UUID: #{uuid}"
    end

    try do
      <<hex::128>> = :binary.bin_to_list(hex_str)
        |> hex_str_to_list
        |> IO.iodata_to_binary
      {type, <<hex::128>>}
    catch
      _, _ ->
        raise ArgumentError, message:
          "Invalid argument; Not a valid UUID: #{uuid}"
    end
  end

  # Get unix epoch as a 60-bit timestamp.
  defp uuid1_time() do
    {mega_sec, sec, micro_sec} = :os.timestamp()
    epoch = (mega_sec * 1_000_000_000_000 + sec * 1_000_000 + micro_sec)
    timestamp = @nanosec_intervals_offset + @nanosec_intervals_factor * epoch
    <<timestamp::60>>
  end

  # Generate random clock sequence.
  defp uuid1_clockseq() do
    <<rnd::14, _::2>> = :crypto.strong_rand_bytes(2)
    <<rnd::14>>
  end

  # Get local IEEE 802 (MAC) address, or a random node id if it can't be found.
  defp uuid1_node() do
    {:ok, ifs0} = :inet.getifaddrs()
    uuid1_node(ifs0)
  end

  defp uuid1_node([{_if_name, if_config} | rest]) do
    case :lists.keyfind(:hwaddr, 1, if_config) do
      :false ->
        uuid1_node(rest)
      {:hwaddr, hw_addr} ->
        if length(hw_addr) != 6 or Enum.all?(hw_addr, fn(n) -> n == 0 end) do
          uuid1_node(rest)
        else
          :erlang.list_to_binary(hw_addr)
        end
    end
  end
  defp uuid1_node(_) do
    <<rnd_hi::7, _::1, rnd_low::40>> = :crypto.strong_rand_bytes(6)
    <<rnd_hi::7, 1::1, rnd_low::40>>
  end

  # Generate a hash of the given data.
  defp namebased_uuid(:md5, data) do
    md5 = :crypto.hash(:md5, data)
    compose_namebased_uuid(@uuid_v3, md5)
  end
  defp namebased_uuid(:sha1, data) do
    <<sha1::128, _::32>> = :crypto.hash(:sha, data)
    compose_namebased_uuid(@uuid_v5, <<sha1::128>>)
  end

  # Format the given hash as a UUID.
  defp compose_namebased_uuid(version, hash) do
    <<time_low::32, time_mid::16, _::4, time_hi::12, _::2,
      clock_seq_hi::6, clock_seq_low::8, node::48>> = hash
    <<time_low::32, time_mid::16, version::4, time_hi::12, @variant10::2,
      clock_seq_hi::6, clock_seq_low::8, node::48>>
  end

  # Identify the UUID variant according to section 4.1.1 of RFC 4122.
  defp variant(<<1, 1, 1>>) do
    :reserved_future
  end
  defp variant(<<1, 1, _v>>) do
    :reserved_microsoft
  end
  defp variant(<<1, 0, _v>>) do
    :rfc4122
  end
  defp variant(<<0, _v::2-binary>>) do
    :reserved_ncs
  end
  defp variant(_) do
    raise ArgumentError, message: "Invalid argument; Not valid variant bits"
  end

  # Binary data to list of hex characters.
  defp binary_to_hex_list(binary) do
    :binary.bin_to_list(binary)
      |> list_to_hex_str
  end

  # Hex string to hex character list.
  defp hex_str_to_list([]) do
    []
  end
  defp hex_str_to_list([x, y | tail]) do
    [to_int(x) * 16 + to_int(y) | hex_str_to_list(tail)]
  end

  # List of hex characters to a hex character string.
  defp list_to_hex_str([]) do
    []
  end
  defp list_to_hex_str([head | tail]) do
    to_hex_str(head) ++ list_to_hex_str(tail)
  end

  # Hex character integer to hex string.
  defp to_hex_str(n) when n < 256 do
    [to_hex(div(n, 16)), to_hex(rem(n, 16))]
  end

  # Integer to hex character.
  defp to_hex(i) when i < 10 do
    0 + i + 48
  end
  defp to_hex(i) when i >= 10 and i < 16 do
    ?a + (i - 10)
  end

  # Hex character to integer.
  defp to_int(c) when ?0 <= c and c <= ?9 do
    c - ?0
  end
  defp to_int(c) when ?A <= c and c <= ?F do
    c - ?A + 10
  end
  defp to_int(c) when ?a <= c and c <= ?f do
    c - ?a + 10
  end

end


###########
# Type: Project Code
# lib/best_effort_broadcast.ex
###########
defmodule BestEffortBroadcast do
  @moduledoc """
  A Best-Effort broadcast implementation.
  This is based on the version provided for the formative coursework with
  changes made for readability, versatility and robustness.

  This implementation differs in that it requires minimal external
  configuration, additionally it differs from the ordinary pattern/architecture
  for modules in that its entry point is entirely booted from an external
  process. This is to reduce complexity in what is otherwise merely a
  convenience module.
  """

  # State for the current module.
  # This is a struct that may be initialized with either the name of the
  # current module, i.e., %BestEffortBroadcast{}, or for more flexibility, the
  # __MODULE__ compilation environment macro may be used, i.e., %__MODULE__{}.

  @enforce_keys [:client, :failed, :broadcast_type]
  defstruct [:client, :failed, :broadcast_type]

  # ---------------------------------------------------------------------------

  # Convenience attribute to specify the default behavior of a failed link.
  # Setting this to true mandates that a failed link send at least one message.
  # Setting this to false, allows for a failed link to not send any message at
  # all.
  # Wherein, failed links refers to links that, for the sake of debugging, are
  # simulating failure.
  @failedLinksStillSend true

  @doc """
  Starts an instance of the BestEffortBroadcast module by creating a delegate
  process and setting it up with the default state (no failures, nominal
  broadcast type.)

  (An external process would call this function to set up an instance of
  BestEffortBroadcast for itself.)

  Returns the PID of the delegate process.
  """
  def start do
    delegate = spawn(__MODULE__, :run, [%__MODULE__{
      client: self(),
      failed: false,
      broadcast_type: :nominal,
    }])

    Process.put("#{__MODULE__}/default_beb_delegate", delegate)
  end

  @doc """
  Sends a broadcast request to the default BestEffortBroadcast delegate for the
  calling process.

  Example usage:
  BestEffortBroadcast.broadcast([:p1, :p2], {:hello, "world"})
  """
  def broadcast(targets, message) do
    case Process.get("#{__MODULE__}/default_beb_delegate") do
      nil -> {__MODULE__, :error, message, targets, "Failed to locate default #{__MODULE__} delegate for process #{self()}! Do you need to specify a PID?"}
      pid -> broadcast(pid, targets, message)
    end
  end

  @doc """
  Similar to broadcast/2 but also requires the delegate PID to be specified
  instead of retrieved from the process dictionary.

  Example usage:
  BestEffortBroadcast.broadcast(pid, [:p1, :p2], {:hello, "world"})
  """
  def broadcast(delegate, targets, message) do
    send(delegate, {__MODULE__, :broadcast, targets, message})
  end

  # The run-state loop. This will execute circularly with tail-end recursion to
  # accept new requests for best-effort broadcasts between processes.
  #
  # The use of this run-state loop takes advantage of Elixir's built-in
  # mailboxes for IPC, enabling the process to enqueue requests if it becomes
  # inundated and process them when it can.
  def run(state) do
    state = receive do
      {__MODULE__, :broadcast, targets, message} ->
        handle_broadcast_request(
          state,
          (if not state.failed, do: targets, else: randomly_drop(targets)),
          message
        )

      {__MODULE__, :ping, pid} ->
        send(state.client, {__MODULE__, :pong, pid})
        state

      {__MODULE__, :debug_set_failed} ->
        %{state | failed: true}

      {__MODULE__, :debug_set_broadcast_type, type} ->
        %{state | type: type}
    end

    # If the process has failed or crashed, exit the best effort broadcast
    # process.
    if state.failed do
      Process.exit(self(), :kill)
    end

    # Perform next iteration of run-state loop.
    run(state)
  end


  # -----------------------
  # END OF PUBLIC INTERFACE
  # -----------------------

  # The following methods are used for debugging implementations. THEY ARE NOT
  # intended for ordinary use, and as such, all of their names are prefaced
  # with debug_.

  def debug_fail(pid) do
    send(pid, {__MODULE__, :debug_set_failed})
  end

  # Debugging method used to configure the simulated type (or state) of links
  # used. Implemented modes are as follows:
  #   :nominal (do not introduce additional behavior)
  #   :reordered (randomize the order and delay after which messages are delivered)
  def debug_change_broadcast_type(pid, type \\ :nominal) do
    send(pid, {__MODULE__, :debug_set_broadcast_type, type})
  end

  # Debugging method used to instantly crash the BEB process.
  def debug_crash do
    Process.exit(self(), :kill)
  end


  # -----------------------
  # END OF DEBUG INTERFACE
  # -----------------------

  # The following methods are private and implementation-dependent ONLY. THEY
  # MUST NOT be accessible to code outside of this module.

  # Delivers a message to the specified target over a point-to-point link.
  defp unicast(state, target, message) do
    case :global.whereis_name(target) do
      pid when is_pid(pid) -> send(pid, message)
      :undefined ->
        send(state.client, {__MODULE__, :error, message, target, "Process #{target} not found!"})
        {__MODULE__, :error, message, target, "Process #{target} not found!"}
    end
  end

  # Implements a broadcast primitive for the Best Effort Broadcast
  # implementation to wrap that simply unicasts the specified message to each
  # of the targets.
  defp broadcast_primitive(state, targets, message) do
    for target <- targets, do: unicast(state, target, message)
  end

  defp randomly_drop(values, ensure_at_least_one \\ @failedLinksStillSend) do
    # Shuffle the values to ensure any value has an equally random chance of
    # being dropped (otherwise the first value would be disproportionately
    # favored.)
    # Then select either:
    #   (ensure_at_least_one = true) 1 or more processes to send the message
    #                                to.
    #   (otherwise) 0 or more processes to send the message to.
    Enum.slice(Enum.shuffle(values), 0, Enum.random(
      (if ensure_at_least_one, do: 1, else: 0)..length(values)
    ))
  end

  # Implements the application logic for handling a broadcast request when
  # the broadcast type is configured to simulate out-of-order messaging.
  defp handle_broadcast_request(state, targets, message) when state.broadcast_type == :reordered do
    spawn(fn ->
      Process.sleep(Enum.random(1..250))
      broadcast_primitive(state, targets, message)
    end)

    state
  end

  # Fallback for application logic to handle a broadcast request where no
  # recognized special circumstances were specified.
  defp handle_broadcast_request(state, targets, message) do
    broadcast_primitive(state, targets, message)
    state
  end
end


###########
# Type: Project Code
# lib/paxos/crypto.ex
###########
defmodule Paxos.Crypto do

  @magicAuthenticationPayload "AB"

  @doc """
  Generates a unique base-64 value of the requested length in bytes
  (default = 64).
  """
  def unique_value(length \\ 64) do
    Base.encode64(:crypto.strong_rand_bytes(length))
  end

  @doc """
  Generates an AES-256 key.
  """
  def generate_key() do
    :crypto.strong_rand_bytes(32)
  end

  @doc """
  Encrypts the payload using the specified key. The value returned is just the
  encrypted payload which may be sent and subsequently used for decryption.
  """
  def encrypt(key, payload) do
    iv = :crypto.strong_rand_bytes(16)

    {cipher_text, cipher_tag} = :crypto.crypto_one_time_aead(
      :aes_256_gcm,
      key, iv, payload,

      # Authentication Data
      @magicAuthenticationPayload,

      # isEncrypting: true = encrypt, false = decrypt
      true
    )

    {iv, cipher_text, cipher_tag}
  end

  @doc """
  Unpacks and decrypts the payload using the specified key, returning the
  result.
  """
  def decrypt(key, payload) do
    {iv, cipher_text, cipher_tag} = payload

    :crypto.crypto_one_time_aead(
      :aes_256_gcm,
      key, iv,
      cipher_text, @magicAuthenticationPayload, cipher_tag,
      false
    )
  end

  @doc """
  Generates a challenge and a solution.

  The solution SHOULD NOT be shared. Doing so might introduce a risk of opening
  up replay attacks.

  Use of a challenge-response means that once the key has been distributed to
  both parties, that key can continue to be re-used without enabling replay
  attacks (provided, obviously that the challenge is instead changed on a
  per-request basis).

  This implementation uses AES-GCM which also verifies message integrity
  through the message authentication tag (integrity check value, ICV). This
  means we can be assured that the message has also not been manipulated in
  transit.
  """
  def create_challenge(key) do
    # Choose a large random integer to serve as a numerator and an always
    # small random integer to serve as divisor.
    challenge = 1001 + random_integer(576460752303422487)
    divisor = 2 + random_integer(7) # Random integer between 3 and 9
                                    # (as l.b. is 1).

    # Solve the problem with integer division.
    solution = div(challenge, divisor)

    # Encrypt the result - this is the challenge.
    challenge = encrypt(key, Integer.to_string(challenge) <> "/" <> Integer.to_string(divisor))

    # Return the challenge and the solution.
    {challenge, solution}
  end

  @doc """
  The implementation necessary to solve a challenge, given a valid key.
  To be solved by the party attempting to prove themselves. The goal here is to
  prove possession of the key.
  """
  def solve_challenge(key, challenge) do
    # Decrypt challenge using key.
    value = decrypt(key, challenge)

    # Parse and solve the challenge.
    parts = String.split(value, "/", trim: true)
    numerator = String.to_integer(Enum.at(parts, 0))
    denominator = String.to_integer(Enum.at(parts, 1))
    solution_attempt = div(numerator, denominator)

    # Then encrypt the result.
    encrypt(key, Integer.to_string(solution_attempt))
  end

  @doc """
  Verifies that the challenge has been successfully solved, by checking that
  the response to the challenge is, indeed, an encrypted form of the solution.
  Returns true if the challenge was solved correctly, otherwise false.
  """
  def verify_challenge_response(key, response, solution) do
    # Decrypt response with key and compare to solution.
    attempted_solution = decrypt(key, response)
    String.to_integer(attempted_solution) == solution
  end

  defp random_integer(max) do
    # Ensure the random number generator has been cryptographically seeded.
    :crypto.rand_seed()
    :rand.uniform(max)
  end

end


###########
# Type: Project Code
# lib/paxos/message.ex
###########
defmodule Paxos.Message do

  require Paxos.Crypto

  defmacro pack(
    command,
    payload,
    other_arguments \\ (quote do (%{reply_to: nil}) end)
  ) do
    quote do: (Map.merge(%{
      protocol: __MODULE__,
      command: unquote(command),
      instance_number: var!(instance_number),
      payload: unquote(payload)
    }, unquote(other_arguments)))
  end

  defmacro pack_encrypted(
    rpc_id,
    command,
    payload,
    metadata,
    other_message_arguments \\ (quote do (%{reply_to: nil}) end)
  ) do
    quote do: ({
      :encrypted,
      unquote(rpc_id),
      Paxos.Crypto.encrypt(unquote(metadata).key,
        :erlang.term_to_binary(%{
          message: Paxos.Message.pack(
            unquote(command),
            unquote(payload),
            unquote(other_message_arguments)
          ),
          challenge_response: Paxos.Crypto.solve_challenge(unquote(metadata).key, unquote(metadata).challenge)
        })
      )
    })
  end

end


###########
# Type: Project Code
# lib/paxos/logger_shim.ex
###########
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


###########
# Type: Project Code
# lib/paxos.ex
###########
defmodule Paxos do

  @moduledoc """
  An Abortable Paxos implementation, as described in Leslie Lamport's "Paxos
  Made Simple" paper.
  """

  # External dependencies.
  use TypedStruct

  # Logger module configuration.
  @loggerModule Logger
#  require Paxos.LoggerShim
  require Logger

  # Paxos sub-modules.
  require Paxos.Message
  require Paxos.Crypto

  # State for the current module.
  # This is a struct that may be initialized with either the name of the
  # current module, i.e., %Paxos{}, or for more flexibility, the __MODULE__
  # compilation environment macro may be used, i.e., %__MODULE__{}.

  typedstruct enforce: true do
    field :name, atom()
    field :participants, list(atom())

    field :current_ballot,
      %{required(integer()) => integer()},
      default: %{}

    # The previously accepted ballot. Initially the ballot number is 0 which
    # means accept whatever the current proposal is (hence the previously
    # accepted ballot value, here, is nil by default.)
    field :accepted,
      # instance_number => {ballot_number, ballot_value}
      %{required(integer()) => {integer(), any()}},
      default: %{}

    # A map of instance number and ballot number to the data held for some
    # ballot.
    # This will only hold that value if the proposal was made to this process
    # and thus this process created a ballot for it - at this time, it is
    # anticipated that any given process will only handle one ballot at once.
    # (i.e., if this process is the leader.)
    field :ballots,
      # {instance_number, ballot_number} => ...
      %{required({integer(), integer()}) => %{
        :proposer => pid(),
        :value => any(),

        # Additional data stored by the application for a ballot it controls.
        :metadata => any(),

        # The list of processes that have prepared or accepted this ballot. It
        # is important that this uses the atom and not the PID, as storing both
        # - or just PIDs - might enable duplicate or invalid processes. Using
        # atoms is easily verifiable as correct and would mean that entries can
        # be cross-checked against :participants.
        # (Once a process has accepted a ballot, its :prepared value will be
        # overwritten with :accepted.)
        :quorum => %{required(atom()) => :prepared | :accepted},

        # See :accepted.
        :greatest_accepted => integer()
      }},
      default: %{}

    # Used to store encryption keys for RPC calls.
    field :keys, %{required(String.t()) => any()}, default: %{}
  end

  # ---------------------------------------------------------------------------

  @doc """
  Starts a delegate instance of the abortable Paxos implementation. Name is an
  alias provided to refer to the **Paxos implementation**.
  The list of participants for Paxos, is (naturally) specified by participants.
  """
  def start(name, participants) do
    if not Enum.member?(participants, name) do
      @loggerModule.error("The Paxos process is not in its own participants list.", [data: [process: name, participants: participants]])
      nil
    else
      # Spawn a process, call Paxos.init with the specified parameters.
      pid = spawn(
        Paxos, :init,
        [name, participants, self()]
      )

      # Register the specified name, (or re-register if it already exists).
      try do
        :global.re_register_name(name, pid)
        Process.register(pid, name)

        # Sleep for a tiny amount of time (10ms) to allow the registration to
        # propagate across the system.
        Process.sleep(10)

        # Registration was successful. Now tell the process it can boot.
        send(pid, :raw_signal_startup)

        # Allow some time for the process to have initialized.
        # This does nothing except potentially make the logs cleaner in
        # interactive mode.
        receive do
          # Process is confirmed to be alive, continue and return PID.
          :raw_signal_startup_complete ->
            @loggerModule.info("Successfully initialized Paxos instance.", [data: [name: name]])

            # Return the process ID of the spawned Paxos instance.
            pid

          # Process has confirmed abort. It should kill itself and we can just
          # return nil.
          :raw_signal_startup_aborted ->
            nil

          # If the process has totally hung or become unresponsive, we will
          # attempt to kill the process.
          after 10000 ->
            if Process.alive?(pid) do
              @loggerModule.error("Paxos delegate initialization timed out. Trying again...")

              # Process failed to acknowledge startup and is now orphaned so
              # attempt to kill it.
              :global.unregister_name(name)
              Process.unregister(name)
              Process.exit(pid, :killed_orphaned)

              # Now attempt to reboot the process.
              @loggerModule.info("Re-attempting to initialize Paxos delegate.", [date: [name: name]])
              Paxos.start(name, participants)
            end
        end
      # Intercept problems to attempt to kill the process gracefully.
      rescue e ->
        send(pid, :raw_signal_kill)
        raise e
      end
    end
  end

  @doc """
  Initializes a process as a Paxos delegate process by creating the necessary
  structures, starting an underlying BestEffortBroadcast instance for that
  process and then starting a run-state loop to handle incoming Paxos requests.
  """
  def init(name, participants, spawner) do
    # Wait for the spawning process to signal that this one can be booted
    # (i.e., that everything has been registered.)
    @loggerModule.info("Waiting for initialize signal...")

    can_continue = receive do
      # If we get the signal / 'go ahead' to initialize, log and then continue.
      :raw_signal_startup ->
        @loggerModule.info("Initializing...")
        :yes
      # Arbitrary kill signal (i.e., external registration failed).
      :raw_signal_kill ->
        @loggerModule.info("Aborted startup.")
        send(spawner, :raw_signal_startup_aborted)
        :no
      # Timeout whilst confirming initialize. Process cannot be registered.
      after 30000 ->
        @loggerModule.error(
          "Timed out whilst waiting for initialize signal. (Did the process fail to register?)"
        )
        :no
    end

    if can_continue == :yes do
      # Now we can begin to initialize and boot this process.
      # Initialize BestEffortBroadcast for this process.
      BestEffortBroadcast.start()

      # Initialize the state and begin the run-state loop.
      state = %Paxos{
        name: name,
        participants: participants
      }

      @loggerModule.notice("Ready! Listening as #{name} (#{inspect(self())}).")
      send(spawner, :raw_signal_startup_complete)
      run(state)
    end
  end

  @doc """
  Propose a given value, value, for the instance of consensus associated with
  instance_number.
  """
  def propose(delegate, instance_number, value, timeout) do
    rpc_paxos(
      # Deliver, to delegate, the following message:
      delegate, Paxos.Message.pack(:propose, {value}, %{reply_to: self()}),
      # After timeout, return the default of :timeout.
      timeout
    )
  end

  @doc """
  Returns the value decided by the consensus associated with instance_number,
  if there was one. Otherwise, returns nil. Also returns nil on timeout.
  """
  def get_decision(delegate, instance_number, timeout) do
    rpc_paxos(
      # Deliver, to delegate...
      delegate,
      # the following message:
      Paxos.Message.pack(:get_decision, {instance_number}, %{reply_to: self()}),
      # After timeout, return nil.
      timeout, nil
    )
  end

  @doc """
  Adds the specified key to the delegate and returns the newly created ID for
  that key. This ID should not be shared.

  Presently, this just relies on MITM starting after the keys are exchanged
  (which for demonstration purposes is kind of a daft assumption given that the
  keys are exchanged every time an RPC occurs) but in a production system, the
  key-exchange could be done on startup to minimize the MITM window. And, to
  beef this up further, PKI could be utilized to rely on asymmetric keys for
  key exchange first which would (in a good PKI implementation) eliminate or
  reduce to negligible concern the risk of MITM.
  """
  def add_key(delegate, key, timeout \\ 5000) do
    response = rpc_raw(delegate, %{
      protocol: __MODULE__,
      command: :add_key,
      reply_to: self(),
      payload: %{
        key: key
      }
    }, timeout)

    # If we got a map back, it worked successfully, so return the key ID,
    # otherwise, return the error tuple.
    if is_map(response), do: response.key, else: response
  end

  # TODO: protect key?
  @doc """
  Deletes the specified key (id) from the delegate.
  """
  def delete_key(delegate, key, timeout \\ 5000) do
    response = rpc_raw(delegate, %{
      protocol: __MODULE__,
      command: :delete_key,
      reply_to: self(),
      payload: %{
        key: key
      }
    }, timeout)

    # If we get a map back, there's no useful information, it worked as
    # intended. Otherwise, there's an error so return it directly.
    if is_map(response), do: nil, else: response
  end


  # TODO: protect key?
  @doc """
  Checks if the specified key (id) is held by the delegate.
  Returns true or false.
  """
  def has_key(delegate, key, timeout \\ 5000) do
    response = rpc_raw(delegate, %{
      protocol: __MODULE__,
      command: :delete_key,
      reply_to: self(),
      payload: %{
        key: key
      }
    }, timeout)

    if is_map(response), do: response.is_held, else: response
  end

  # -----------------------
  # END OF PUBLIC INTERFACE
  # -----------------------

  # ---------------------------------------------------------------------------

  # Paxos.propose - Step 1 - Leader -> All Processes
  # Create a new ballot, b.
  # Broadcast (prepare, b) to all processes.
  defp paxos_propose(state, instance_number, reply_to, {value}, metadata) do
    # If the current_ballot number for this instance does not exist, initialize
    # it to 0.
    state = %{state |
      current_ballot: Map.put_new(state.current_ballot, instance_number, 0)}

    # Fetch and increment the current ballot number for this instance.
    current_ballot = Map.fetch!(state.current_ballot, instance_number) + 1

    BestEffortBroadcast.broadcast(
      state.participants,
      Paxos.Message.pack(
        # -- Command
        :prepare,

        # -- Data
        # We prepare the next ballot (after the current one) for voting on.
        %{ballot: current_ballot, value: value},

        # -- Additional Options
        # Send replies to :prepare to the Paxos delegate - not the client.
        %{reply_to: self()}
      )
    )

    # Add this proposal to the list of ballots this leader is currently
    # working on.
    state = %{state
      | ballots: Map.put(
        state.ballots, {instance_number, current_ballot},
        %{
          proposer: reply_to,
          value: value,
          metadata: metadata,
          quorum: %{},
          greatest_accepted: 0
        }
      )
    }

    # We won't reply to the propose request immediately. Instead, we will
    # handle this internally and send the reply when we're ready, elsewhere.
    # Returning from this RPC with :skip_reply means we won't send the reply
    # and thus the requestor will continue to wait for a reply (either until
    # it gets one, or until it times out.)
    %{result: :skip_reply, state: state}
  end

  # Paxos.propose - Step 2 - All Processes -> Leader
  # Check if the incoming ballot is greater than the current one. If it is,
  # send :prepared to reply_to.
  # Otherwise, send :nack.
  defp paxos_prepare(state, instance_number, reply_to, %{ballot: ballot}) do
    # If the current_ballot number for this instance does not exist, initialize
    # it to 0. Likewise, initialize accepted for this instance.
    state = %{state |
      current_ballot: Map.put_new(state.current_ballot, instance_number, 0),
      accepted: Map.put_new(state.accepted, instance_number, {0, nil})}

    if ballot > state.current_ballot[instance_number] do
      # If the new ballot is greater than any current ballot, tell the leader
      # we're prepared to accept this as our current ballot and indicate to
      # ourselves that we've seen at least this ballot (if the ballot is later
      # rejected, unless we're the leader we don't care but we shouldn't be
      # able to re-prepare that ballot, so incrementing current_ballot here
      # is fine - if we are the leader, that logic is handled elsewhere, in the
      # other stages, anyway).
      send(reply_to, Paxos.Message.pack(:prepared, %{
        process: state.name,
        ballot: ballot,
        accepted: state.accepted[instance_number],
      }))

      %{
        result: :skip_reply,
        state: %{state | current_ballot: Map.put(state.current_ballot, instance_number, ballot)}
      }
    else
      # If we've already processed this ballot, or a ballot after this one, we
      # must not accept it and instead indicate that we've rejected it (i.e.,
      # not acknowledged, nack).
      send(reply_to, Paxos.Message.pack(:nack, %{ballot: ballot}))
      %{result: :skip_reply, state: state}
    end
  end

  # Paxos.propose - Step 3 - Leader -> All Processes
  # Check if the incoming ballot is greater than the current one. If it is,
  # send :prepared to reply_to.
  # Otherwise, send :nack.
  defp paxos_prepared(state, instance_number, %{
    process: process_name,
    accepted: process_last_accepted,
    ballot: ballot_number
  }) do
    # Check if the ballot is one we've registered as one we're leading.
    state = with ballot when ballot != nil <- Map.get(state.ballots, {instance_number, ballot_number}) do

      # Add the process that has indicated prepared to the quorum map.
      ballot = %{ballot | quorum: Map.put(ballot.quorum, process_name, :prepared)}

      # Store the accepted value in ballot.greatest_accepted. This is to keep
      # track of the accepted value FROM THE PROCESS THAT HAS THE HIGHEST
      # PREVIOUSLY ACCEPTED BALLOT.
      ballot = if elem(process_last_accepted, 0) > ballot.greatest_accepted do
        # If this accepted value is higher than the current one, use it (this
        # should be accepted instead of the initially proposed value).
        %{ballot |
          greatest_accepted: elem(process_last_accepted, 0),
          value: elem(process_last_accepted, 1)}
      else
        # Otherwise, there's no need to do anything.
        ballot
      end

      # Update the changes to ballot within state, before continuing.
      state = %{state | ballots: Map.put(state.ballots, {instance_number, ballot_number}, ballot)}

      # If quorum reached, broadcast accept (otherwise do nothing).
      if upon_quorum_for(
        :prepared,
        state.ballots[{instance_number, ballot_number}].quorum,
        state.participants
      ) do
        BestEffortBroadcast.broadcast(
          state.participants,
          Paxos.Message.pack(
            # -- Command
            :accept,

            # -- Data
            # We indicate the decided ballot value for the given ballot number.
            %{ballot: ballot_number, value: ballot.value},

            # -- Additional Options
            # Send replies to :accept to the Paxos delegate - not the client.
            %{reply_to: self()}
          )
        )
      end

      state
    else
      _ ->
        # This response is returned for future use, but currently will just be
        # thrown away. This is fine, we can safely disregard them - it's likely
        # that we aborted the ballot and other processes are catching up.
        {:error, "The requested proposal, instance #{instance_number}, ballot #{ballot_number}, could not be found. This process probably isn't the leader for this instance."}
        state
    end

    %{result: :skip_reply, state: state}
  end

  defp paxos_accept(state, instance_number, reply_to, %{
    ballot: ballot, value: value
  }) do
    if ballot >= state.current_ballot[instance_number] do

      # Mark the ballot as accepted and update the current ballot number to
      # reflect the last ballot we've processed.
      state = %{state |
        current_ballot: Map.put(state.current_ballot, instance_number, ballot),
        accepted: Map.put(state.accepted, instance_number, {ballot, value}),
      }

      # Now send :accepted to indicate we've done so.
      send(reply_to, Paxos.Message.pack(:accepted, %{
        process: state.name,
        ballot: ballot
      }))

      %{
        result: :skip_reply,
        state: state
      }
    else
      # If we've already processed this ballot, or a ballot after this one, we
      # must not accept it and instead indicate that we've rejected it (i.e.,
      # not acknowledged, nack).
      send(reply_to, Paxos.Message.pack(:nack, %{ballot: ballot}))
      %{result: :skip_reply, state: state}
    end
  end

  defp paxos_accepted(state, instance_number, %{process: process_name, ballot: ballot_number}) do
    # Check if the ballot is one we've registered as one we're leading.
    state = with ballot when ballot != nil <- Map.get(state.ballots, {instance_number, ballot_number}) do

      # Add the process that has indicated accepted to the quorum map.
      ballot = %{ballot | quorum: Map.put(ballot.quorum, process_name, :accepted)}

      # Update the changes to ballot within state, before continuing.
      state = %{state | ballots: Map.put(state.ballots, {instance_number, ballot_number}, ballot)}

      if upon_quorum_for(
        :accepted,
        state.ballots[{instance_number, ballot_number}].quorum,
        state.participants
      ) do
        # We've reached a quorum of :accepted! Yay! Consensus achieved.
        @loggerModule.notice("Successfully achieved consensus", [data: [leader: state.name, instance: instance_number, ballot: ballot_number, value: ballot.value]])

        # Delete the ballot from state. It's no longer needed.
        state = %{state
          | ballots: Map.delete(state.ballots, {instance_number, ballot_number})
        }

        # Return decision by replying to the client's propose message.
        send(
          ballot.proposer,
          Paxos.Message.pack_encrypted(
            ballot.metadata.rpc_id, :propose,
            {:decision, ballot.value},
            %{
              key: state.keys[ballot.metadata.key],
              challenge: ballot.metadata.challenge
            }
          )
        )

        state
      else
        state
      end
    else
      _ ->
        # This response is returned for future use, but currently will just be
        # thrown away. This is fine, we can safely disregard them - it's likely
        # that we aborted the ballot and other processes are catching up.
        {:error, "The requested proposal, instance #{instance_number}, ballot #{ballot_number}, could not be found. This process probably isn't the leader for this instance."}
        state
    end

    %{result: :skip_reply, state: state}
  end

  defp paxos_nack(state, instance_number, %{ballot: ballot_number}) do
    # If the instance_number is in the list of ballots we're currently
    # processing, then remove it and abort.
    state = with ballot when ballot != nil <- Map.get(state.ballots, {instance_number, ballot_number}) do
      # Update the state to show the status of this ballot.
      state = %{state |
        ballots: Map.delete(state.ballots, {instance_number, ballot_number})
      }

      # Return abort by replying to the client's propose message.
      send(
        ballot.proposer,
        Paxos.Message.pack_encrypted(
          ballot.metadata.rpc_id,
          :propose, {:abort}, %{
            key: state.keys[ballot.metadata.key],
            challenge: ballot.metadata.challenge
          }
        )
      )

      state
    end

    %{result: :skip_reply, state: state}
  end



  # Paxos.get_decision - Step 1 of 1
  # Returns the decision that was arrived at for the specified instance_number.
  defp paxos_get_decision(state, instance_number, reply_to, {instance_number}, metadata) do
    # Check if there is an accepted value for that instance_number, and check
    # that the ballot number is greater than zero.
    result = if Map.has_key?(state.accepted, instance_number)
      and elem(state.accepted[instance_number], 0) > 0 do

      # Return the latest accepted value for that instance_number.
      elem(state.accepted[instance_number], 1)

    else
      nil
    end

    # Send the reply back to the client.
    send(
      reply_to,
      Paxos.Message.pack_encrypted(
        metadata.rpc_id,
        :get_decision, result, %{
          key: state.keys[metadata.key],
          challenge: metadata.challenge
        }
      )
    )

    :skip_reply
  end


  # ---------------------------------------------------------------------------

  # The run-state loop.
  # Used to answer messages whilst keeping track of application state.
  defp run(state) do
    state = receive do
      message -> handle_message(state, message)
    end

    run(state)
  end

  defp handle_message_middlewares(state, message) do
    message = case message do
      {:encrypted, rpc_id, encrypted_payload, key_id} ->
        # Decrypt and decode the message and challenge using the requested key.
        %{message: message, challenge: challenge} = :erlang.binary_to_term(
          Paxos.Crypto.decrypt(state.keys[key_id], encrypted_payload)
        )

        # Inject the key ID and challenge into the message as part of the
        # metadata.
        message = Map.merge(%{metadata: %{}}, message)
        %{message | metadata: Map.merge(message.metadata, %{rpc_id: rpc_id, key: key_id, challenge: challenge})}

      # In any case, if the message is a map, inject the metadata property.
      _ -> if is_map(message), do: Map.merge(%{metadata: %{}}, message), else: message
    end

    {state, message}
  end

  # Handles an incoming message by mutating the state and returning the updated
  # state. Additionally, checks if there are middlewares for this message and
  # processes them if there are by calling handle_message_middlewares/2.
  defp handle_message(state, message) do

    # Before we attempt to process the message, first check if there are
    # middlewares for this message that need to be executed.
    {state, message} = handle_message_middlewares(state, message)

    case message do
      # Paxos Commands
      %{
        # This block will only handle messages defined in the current module.
        protocol: __MODULE__,
        command: command,
        instance_number: instance_number,
        reply_to: reply_to,
        payload: payload,
        metadata: metadata
      } ->
        # Handle pre-set commands specified with the Paxos implementation
        # protocol by executing the appropriate handler function. Before we do,
        # we'll log the message for debugging purposes.
        @loggerModule.debug("✉️", [data: %{
          protocol: __MODULE__,
          command: command,
          instance_number: instance_number,
          reply_to: reply_to,
          payload: payload
        }])

        raw_result = case command do
          # Local State Control Commands (generally paxos_rpc)
          # --------------------------------------------------
          # A client process outside of the Paxos implementation issues these
          # requests to a Paxos delegate process (participant) with
          # Paxos.propose/4 or Paxos.get_decision/3, etc.,
          :propose -> paxos_propose(state, instance_number, reply_to, payload, metadata)
          :get_decision -> paxos_get_decision(state, instance_number, reply_to, payload, metadata)

          # Broadcast Commands (generally broadcasted)
          # ------------------------------------------
          # These are commands sent to other processes as part of the Paxos
          # processes (usually broadcasted).
          :prepare -> paxos_prepare(state, instance_number, reply_to, payload)
          :prepared -> paxos_prepared(state, instance_number, payload)
          :accept -> paxos_accept(state, instance_number, reply_to, payload)
          :accepted -> paxos_accepted(state, instance_number, payload)
          :nack -> paxos_nack(state, instance_number, payload)

          # Fallback Handler
          # ----------------
          # If the command is unknown, this prevents a crash and instead
          # replies with a message indicating that the requested command was
          # unknown.
          _ ->
            @loggerModule.warn("Received bad/unknown command, #{inspect command}.")
            {:error, "Bad/unknown command specified."}
        end

        # If a map containing just result and state is returned, interpret
        # result as the return value and state as the replacement state.
        # Otherwise, leave the state alone and just return whatever the
        # resulting value is.
        %{result: result, state: new_state} =
          if is_map(raw_result) and Map.keys(raw_result) -- [:result, :state] == [],
            do: raw_result,
            else: %{result: raw_result, state: nil}

        # Reflect the changes in the state, if there were any by the command
        # delegate.
        state = if new_state != nil, do: new_state, else: state

        # Send the reply yielded from executing a command back to the client,
        # again with the Paxos implementation protocol.
        if reply_to != nil and result != :skip_reply do
          send(
            reply_to,
            Paxos.Message.pack(command, result)
          )
        end

        # Finally, respond with the state.
        state

      # End Paxos Commands.

      # General Commands.
      # These commands are not directly related to the Paxos protocol, and are
      # instead used for additional functionality.
      %{
        protocol: __MODULE__,
        command: command,
        reply_to: reply_to,
        payload: payload,
        metadata: _
      } ->
        @loggerModule.debug("⚙️", [data: %{
          protocol: __MODULE__,
          command: command,
          reply_to: reply_to,
          payload: payload
        }])

        case command do
          :add_key ->

            # If the payload contains a key, accept the key, generate a unique
            # ID for it, and return the ID.

            if not Map.has_key?(payload, :key) do
              send(reply_to, %{ protocol: __MODULE__, command: command, payload: {:error, "Request missing attribute :key."} })
              state
            else
              # TODO: check if key itself already exists?

              # Recursively generate a new key ID until we arrive at a UUID not
              # already used as a key ID.
              # This should almost never recur, but we do this on the off chance
              # an implementation is dodgy or the 'impossible' happens to recover
              # gracefully.
              generate_new_key_id = fn
                recur -> uuid = UUID.uuid4()
                if Map.has_key?(state.keys, uuid),
                  do: recur.(recur),
                  else: uuid
              end

              key_id = generate_new_key_id.(generate_new_key_id)

              # Return a message with the ID to indicate success.
              send(reply_to, %{
                protocol: __MODULE__,
                command: command,
                payload: %{
                  key: key_id
                }
              })

              # Finally, write the key into storage.
              %{state | keys: Map.put(state.keys, key_id, payload.key)}
            end

          :delete_key ->

            # If the payload contains a key to drop, drop it, if it exists.
            if not Map.has_key?(payload, :key) do
              send(reply_to, %{ protocol: __MODULE__, command: command, payload: {:error, "Request missing attribute :key."} })
              # Leave state unaltered.
              state
            else

              if Map.has_key?(state.keys, payload.key) do
                # Return a message indicating that the key no longer exists by
                # reflecting the success message but where key is nil.
                send(reply_to, %{
                  protocol: __MODULE__,
                  command: command,
                  payload: %{
                    key: nil
                  }
                })

                %{state | keys: Map.delete(state.keys, payload.key)}
              else
                # Return an error message to indicate inability to find the
                # key.
                send(reply_to, %{
                  protocol: __MODULE__,
                  command: command,
                  payload: {:error, "The requested key could not be found."}
                })

                # Do nothing to state.
                state
              end

            end

          :has_key ->
            # If the payload contains a key to check, return the status of
            # whether the key is held.
            if not Map.has_key?(payload, :key) do
              send(reply_to, %{ protocol: __MODULE__, command: command, payload: {:error, "Request missing attribute :key."} })
            else
              send(reply_to, %{
                protocol: __MODULE__,
                command: command,
                payload: %{
                  is_held: Map.has_key?(state.keys, payload.key)
                }
              })
            end

            # Do nothing with the state.
            state
        end
      # End General Commands.

      # Handle error messages by logging them.
      error_message when is_tuple(error_message) and elem(error_message, 0) == :error or elem(error_message, 1) == :error ->
        @loggerModule.warn("Received error message.", [data: error_message])
        state

      # Ignore unrecognized messages.
      _ ->
        state
    end

  end

  # ---------------------------------------------------------------------------

  # -----------------------
  # UTILITY METHODS
  # -----------------------

  # TODO: implement message counters for RPC?

  # Used to execute an unauthenticated, standard RPC to some target process,
  # and get a response, within some time frame. After the time frame has
  # expired, :timeout is returned instead.
  defp rpc_raw(target, message, timeout, value_on_timeout \\ {:timeout}) do
    # Send the message to the delegate.
    send(target, message)

    # Wait for a reply that satisfies the conditions, then return the payload
    # from the reply.
    receive do
      reply when
        reply.protocol == message.protocol and
        reply.command == message.command -> reply.payload

    # Or alternatively, time out.
    after timeout -> value_on_timeout
    end
  end

  # Used by calling process (i.e., a client) to execute a remote procedure call
  # to a Paxos delegate, and get a response.
  defp rpc_paxos(delegate, message, timeout, value_on_timeout \\ {:timeout}) do
    rpc_id = Paxos.Crypto.unique_value()

    # Keys can be exchanged at any time (e.g., on startup/initialization), but
    # for demonstration purposes, they are exchanged here.
    key = Paxos.Crypto.generate_key()

    # Send the key to the Paxos delegate for the lifecycle of this RPC.
    key_id = Paxos.add_key(delegate, key)

    # Create the challenge and solution.
    {challenge, solution} = Paxos.Crypto.create_challenge(key)

    # Send the message to the delegate, encrypted and include the challenge.
    send(delegate, {:encrypted, rpc_id, Paxos.Crypto.encrypt(key, :erlang.term_to_binary(%{
      message: message,
      challenge: challenge
    })), key_id})

    # Wait for a reply that satisfies the conditions, then return the payload
    # from the reply.
    receive do
      {:encrypted, incoming_rpc_id, encoded} when rpc_id == incoming_rpc_id ->
        payload = Paxos.Crypto.decrypt(key, encoded)

        if payload != :error do

          %{
            message: reply,
            challenge_response: challenge_response
          } = :erlang.binary_to_term(payload)

          # The key is no longer needed, it can be deleted from the Paxos
          # delegate.
          Paxos.delete_key(delegate, key_id)

          if (
            # Verify payload headers.
            reply.protocol == message.protocol and
            reply.command == message.command and
            reply.instance_number == message.instance_number and
            reply.reply_to == nil and
            # Verify challenge-response.
            Paxos.Crypto.verify_challenge_response(key, challenge_response, solution)) do
              # If the reply checks out, return the payload.
              reply.payload
          else
            # Otherwise, return the timeout value.
            value_on_timeout
          end

        else
          value_on_timeout
        end

    # Or alternatively, time out.
    after timeout -> value_on_timeout
    end
  end

  # Checks if, for a given status, there is a quorum out of the total
  # processes.
  #
  # status = the status atom to check if a quorum of processes has arrived at,
  #          e.g., :prepared or :accepted
  # quorum_state = state.ballots[{instance_number, ballot_number}].quorum
  # all_participants = state.participants
  defp upon_quorum_for(status, quorum_state, all_participants) do
    # number_of_elements >= div(total, 2) + 1

    IO.puts(inspect quorum_state)

    # Count the number of elements whose value matches the status.
    number_of_elements =
      Map.filter(quorum_state, fn {_, v} -> v == status end)
      |> Enum.count

    # Count the total number of participants in the system.
    total = length(all_participants)

    # Now return whether or not the number of nodes in the required condition
    # is equal to floor(total / 2) + 1 (i.e., a majority).
    number_of_elements == div(total, 2) + 1
  end

  # ---------------------------------------------------------------------------

  # -----------------------
  # DEBUG INTERFACE
  # -----------------------

end


