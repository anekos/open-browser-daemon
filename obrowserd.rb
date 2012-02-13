#!/usr/bin/ruby
# vim:set fileencoding=utf-8 :

require 'socket'
require 'uri'
require 'optparse'
require 'cgi'


class Options
  Items = [:daemon, :host, :port]
  attr_reader *Items

  def initialize (argv)
    @host = 0
    @port = 80
    parse(argv)
  end

  private

  def load_config (source)
    data = YAML.load(source)
    Items.each do
      |it|
      [it, it.to_s].each do
        |name|
        instance_variable_set("@#{it}", data[name]) if data.include?(name)
      end
    end
  end

  def parse (argv)
    argv = argv.dup
    opts = OptionParser.new
    opts.on('-d', '--daemon') {|v| @daemon = true }
    opts.on('-h', '--host HOST') {|v| @host = v }
    opts.on('-p', '--port PORT') {|v| @port = v.to_i }
    opts.on('-f', '--config-file FILE', 'YAML format') {|v| load_config(File.read(v)) }
    opts.parse(argv)
  rescue OptionParser::ParseError => e
    puts e
    puts opts.help
    exit 1
  end
end


class OpenBrowserDaemon
  def initialize (options)
    @options = options
  end

  def start
    server = TCPServer.open(@options.host, @options.port)

    while true
      Thread.start(server.accept) do
        |socket|
        begin
          puts("#{socket} is accepted")

          first = socket.gets.chomp
          if http = first.match(/\AGET \/?(\S+) HTTP\/1\.\d\Z/)
            open_path(URI.decode_www_form_component(http[1]))
            socket.puts(http_response(http[1]))
          else
            open_path(first)
            socket.puts('OK')
            while line = socket.gets
              open_path(line.chomp)
              socket.puts('OK')
            end
          end

          puts("#{socket} is gone")
        rescue Exception => e
          STDERR.puts e
        ensure
          socket.close
        end
      end
    end
  end

  private

  # open_path method
  case RUBY_PLATFORM
  when /mswin(?!ce)|mingw|cygwin|bccwin/i
    require 'win32api'

    ShellExecute = Win32API.new('shell32.dll', 'ShellExecute', %w(p p p p p i), 'i')

    def open_path (path)
      puts("Open: #{path}")
      ShellExecute.call(0, 'open', path, 0, 0, 1)
    end
  when /linux/i
    require 'shellwords'

    def which (cmd)
      ENV['PATH'].split(':').any? {|it| test(?x, File.join(it, cmd)) }
    end

    def open_path (path)
      cmd = %w[xdg-open gnome-open].find {|it| which(it) }
      raise 'No open command' unless cmd
      system("#{cmd} #{Shellwords.escape(path)}")
    end
  end

  def http_response (path)
    return <<EOM
HTTP/1.0 200 OK
Content-Type: text/html
Connection: Close

<html>
  <head>
    <title>Opened #{path}</title>
  </head>
  <body>
    <h1>Opened</h1>
    <p>#{CGI.escapeHTML(path)}</p>
  </body>
</html>
EOM
  end
end


OpenBrowserDaemon.new(Options.new(ARGV)).start

