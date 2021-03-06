require 'cant_fire/version'

module CantFire
  extend self

  def new_message &block
    rooms   = @rooms
    room    = $room || rooms.first
    message = $message

    file = File.expand_path('~/.cant_fire_message')

    File.open(file, 'w') do |m|
      m.puts message ? "#{message.user.name}: " : ''
      m.puts
      m.puts "# room: #{room.name}"
      m.puts "#"
      rooms.each do |r|
        users   = @users[r.name] || []
        m.puts "# #{(r.name+':').ljust 20} #{users.map(&:name).map(&:inspect).join(', ')}"
      end
    end
    system [ENV['EDITOR'], file].join(' ')
    full_message = File.read(file)
    message = full_message.lines.select { |l| l !~ /^\s*#/ }.join('')
    room = rooms.find{|r| r.name == $1} if full_message =~ /^# room: (.*)$/
    room.speak message.strip unless message.strip.empty?
    block.call
  end


  def start!
    require 'term/ansicolor'
    require 'thread'
    require 'tinder'
    require 'shellwords'


    String.send :include, Term::ANSIColor

    colors = %w[red green yellow blue magenta cyan white]

    room_colors = {all: colors.dup}
    user_colors = {all: colors.dup}
    @rooms = campfire.rooms
    @users = {}
    @rooms_threads = @rooms.map do |room|
      next if config.skip_rooms.include? room.name
      @users[room.name] = room.users
      Thread.new do
        room_colors[:all] = colors.dup if room_colors[:all].empty?
        room_colors[room.name] ||= room_colors[:all].shift
        room_color = room_colors[room.name]

        puts "Connecting to #{room.name.inspect}".send(room_color)
        room.listen do |message|
          next unless message.body and message.user

          $room = room
          $message = message

          user = message.user

          user_colors[:all] = colors.dup if user_colors[:all].empty?
          user_colors[user.name] ||= user_colors[:all].shift
          user_color = user_colors[user.name]
          message_body = message.body

          case message.body
          when /(#{config.username}|\ball\b)/i
            message_body = message_body.yellow
            url = "https://#{config.subdomain}.campfirenow.com/room/#{room.id}#message_#{message.id}"
            notify message.body,
                   title:    "#{user.name} is calling you!",
                   subtitle: room.name,
                   open:     url,
                   group:    "Campfire - #{room.name}"
            # Notify.notify summary, message.body
            # Notify.notify "New message on room #{room.name.inspect}: \n#{message.body}"
          end
          puts "[#{room.name}] ".send(room_color) +
               "**#{user.name}**:".send(user_color) +
               " #{message_body}"

        end
      end
    end.compact


    begin
      puts 'Hit CTRL+C to write a message'
      sleep 1 until $exit
    rescue Interrupt
      if $interrupted
        $exit = true
      else
        $interrupted = true
        puts 'Hit CTRL+C to exit'
        sleep 0.5
        CantFire.new_message { $interrupted = false }
        retry
      end
    end
    @rooms_threads.each(&:exit)
    exit
  end


  class ConfigError < StandardError
  end

  def check_config!
    config
  end


  private

  def config
    @config ||= begin
      require 'ostruct'
      require 'yaml'

      config_path = File.expand_path('~/.cant_fire')
      raise ConfigError.new("Please setup your config file first in: #{config_path}") unless File.exist? config_path
      OpenStruct.new YAML.load_file(config_path)
    end
  end

  def campfire
    @campfire ||= begin
      Tinder::Campfire.new config.subdomain, :token => config.token
    end
  end

  def puts *args
    print args.join("\n") << "\n"
  end

  def notify message, options
    fork { exec "say #{options[:title].shellescape}" }
    if config.terminal_notifier
      require 'terminal-notifier'
      # TerminalNotifier.notify('Hello World', :title => 'Ruby', :subtitle => 'Programming Language')
      # TerminalNotifier.notify('Hello World', :activate => 'com.apple.Safari')
      # TerminalNotifier.notify('Hello World', :open => 'http://twitter.com/alloy')
      # TerminalNotifier.notify('Hello World', :execute => 'say "OMG"')
      # TerminalNotifier.notify('Hello World', :group => Process.pid)
      TerminalNotifier.notify(message, options)
    end
  end
end
