#
# Copyright:: Copyright (c) 2018 Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "mixlib/cli"
require "chef-workstation/config"
require "chef-workstation/text"
require "chef-workstation/log"
require "chef-workstation/error"
require "chef-workstation/ui/terminal"

module ChefWorkstation
  module Command
    class Base
      include Mixlib::CLI
      T = Text.commands.base

      # All the actual commands have their banner managed and set from the commands map
      # Look there to see how we set this in #create
      banner "Command banner not set."

      option :version,
        :short        => "-v",
        :long         => "--version",
        :description  => T.version,
        :boolean      => true

      option :help,
        :short        => "-h",
        :long         => "--help",
        :description  => T.help,
        :boolean      => true

      option :config_path,
        :short        => "-c PATH",
        :long         => "--config PATH",
        :description  => T.config(ChefWorkstation::Config.default_location),
        :default      => ChefWorkstation::Config.default_location,
        :proc         => Proc.new { |path| ChefWorkstation::Config.custom_location(path) }

      def initialize(command_spec)
        @command_spec = command_spec
        super()
      end

      def run_with_default_options(params = [])
        # Each subcommand gets its own help subcommand which is really the class
        # as its parent.  If the name of the command is help,
        # ignore options and just display help.
        if params.include?("-h") || params.include?("--help")
          # We ignore options for all 'help' commands.
          Log.debug "Showing help for #{@command_spec.qualified_name}"
          show_help
        else
          Log.debug "Starting #{@command_spec.qualified_name} command"
          parse_options(params)
          run(params)
        end
        Log.debug "Completed #{@command_spec.qualified_name} command without exception"
      end

      def run(params)
        show_help
      end

      # The visual progress aspect of connecting will be common to
      # many commands, so we provide a helper to the in this base class.
      # If reporter is nil a Terminal spinner will be used; otherwise
      # the provided reporter will be used.
      def connect(target, settings, reporter = nil)
        conn = RemoteConnection.new(target, settings)
        if reporter.nil?
          UI::Terminal.spinner(T.status.connecting, prefix: "[#{conn.config[:host]}]") do |rep|
            conn.connect!
            rep.success(T.status.connected)
          end
        else
          reporter.update(T.status.connecting)
          conn = conn.connect!
          reporter.success(T.status.connected)
        end
        conn
      rescue RuntimeError => e
        if reporter.nil?
          UI::Terminal.output(e.message)
        else
          reporter.error(e.message)
        end
        raise
      end

      def self.usage(usage = nil)
        if usage.nil?
          @usage
        else
          @usage = usage
        end
      end

      def usage
        self.class.usage
      end

      private

      # TODO - does this all just belong in a HelpFormatter? Seems weird
      # to encumber the base with all this...
      def show_help
        root_command = @command_spec.qualified_name == "hidden-root"
        if root_command
          UI::Terminal.output T.version_for_help(ChefWorkstation::VERSION)
        end
        UI::Terminal.output banner
        show_help_flags unless options.empty?
        show_help_subcommands unless subcommands.empty?
        if root_command && ChefWorkstation.commands_map.alias_specs.length > 0
          show_help_aliases
        end
      end

      def show_help_flags
        UI::Terminal.output ""
        UI::Terminal.output "FLAGS:"
        justify_length = 0
        options.each_value do |spec|
          justify_length = [justify_length, spec[:long].length + 4].max
        end
        options.sort.to_h.each_value do |flag_spec|
          short = flag_spec[:short] || "  "
          short = short[0, 2] # We only want the flag portion, not the capture portion (if present)
          if short == "  "
            short = "    "
          else
            short = "#{short}, "
          end
          flags = "#{short}#{flag_spec[:long]}"
          UI::Terminal.write("    #{flags.ljust(justify_length)}    ")
          ml_padding = " " * (justify_length + 8)
          first = true
          flag_spec[:description].split("\n").each do |d|
            UI::Terminal.write(ml_padding) unless first
            first = false
            UI::Terminal.write(d)
            UI::Terminal.write("\n")
          end
        end
      end

      def show_help_subcommands
        UI::Terminal.output ""
        UI::Terminal.output "SUBCOMMANDS:"
        justify_length = ([7] + subcommands.keys.map(&:length)).max + 4
        display_subcmds = subcommands.dup
        # A bit of management to ensure that 'help' and version are the last displayed subcommands

        help_cmd = display_subcmds.delete("help")
        version_cmd = display_subcmds.delete("version")
        display_subcmds.sort.each do |name, spec|
          next if spec.hidden
          UI::Terminal.output "    #{"#{name}".ljust(justify_length)}#{spec.text.description}"
        end

        unless help_cmd.nil?
          UI::Terminal.output "    #{"#{help_cmd.name}".ljust(justify_length)}#{T.help}"
          UI::Terminal.output "    #{"#{version_cmd.name}".ljust(justify_length)}#{T.help}"
        end
      end

      def show_help_aliases
        justify_length = ([7] + ChefWorkstation.commands_map.alias_specs.keys.map(&:length)).max + 4
        UI::Terminal.output ""
        UI::Terminal.output(T.aliases)
        ChefWorkstation.commands_map.alias_specs.sort.each do |name, spec|
          next if spec.hidden
          UI::Terminal.output "    #{"#{name}".ljust(justify_length)}#{T.alias_for} '#{spec.qualified_name}'"
        end
      end

      def subcommands
        # The base class behavior subcommands are actually the full list
        # of top-level commands - those are subcommands of 'chef'.
        # In a future pass, we may want to actually structure it that way
        # such that a "Base' instance named 'chef' is the root command.
        @command_spec.subcommands
      end

      class OptionValidationError < ChefWorkstation::ErrorNoLogs
        attr_reader :command
        def initialize(id, calling_command, *args)
          super(id, *args)
          # TODO - this is getting cumbersome - move them to constructor options hash in base
          @decorate = false
          @command = calling_command
        end
      end

    end
  end
end
