# $Id$

require 'logging/appender'

module Logging::Appenders

  # This class provides an Appender that can send notifications to the Growl
  # notification system on Mac OS X.
  #
  # +growlnotify+ must be installed somewhere in the path in order for the
  # appender to function properly.
  #
  class Growl < ::Logging::Appender

    # call-seq:
    #    Growl.new( name, opts = {} )
    #
    # Create an appender that will log messages to the Growl framework on a
    # Mac OS X machine.
    #
    def initialize( name, opts = {} )
      super

      @growl = "growlnotify -w -n \"#{@name}\" -t \"%s\" -m \"%s\" -p %d &"

      @coalesce = opts.getopt(:coalesce, false)
      @title_sep = opts.getopt(:separator)

      # provides a mapping from the default Logging levels
      # to the Growl notification levels
      @map = [-2, -1, 0, 1, 2]

      map = opts.getopt(:map)
      self.map = map unless map.nil?

      # make sure the growlnotify command can be called
      if system('growlnotify -v 2&>1 > /dev/null')
        setup_coalescing if @coalesce
      else
        self.level = :off
        # TODO - log that the growl notification is turned off
      end
    end

    # call-seq:
    #    map = { logging_levels => growl_levels }
    #
    # Configure the mapping from the Logging levels to the Growl
    # notification levels. This is needed in order to log events at the
    # proper Growl level.
    #
    # Without any configuration, the following maping will be used:
    #
    #    :debug  =>  -2
    #    :info   =>  -1
    #    :warn   =>  0
    #    :error  =>  1
    #    :fatal  =>  2
    #
    def map=( levels )
      map = []
      levels.keys.each do |lvl|
        num = ::Logging.level_num(lvl)
        map[num] = growl_level_num(levels[lvl])
      end
      @map = map
    end


    private

    # call-seq:
    #    write( event, do_layout = true )
    #
    # Write the given _event_ to the growl notification facility. The log
    # event will be processed through the Layout assciated with this
    # appender if the _do_layout_ flag is set to +true+. The message will be
    # logged at the level specified by the event.
    #
    # If the _do_layout_ flag is set to +false+, the _event_ will be
    # converted to a string and wirtten to the growl notification facility
    # "as is" -- no layout formatting will be performed. The string will be
    # logged at the 0 notification level of the Growl framework.
    #
    def write( event, do_layout = true )
      title = ''
      priority = 0
      message = if do_layout
          priority = @map[event.level]
          @layout.format(event)
        else
          event.to_s
        end

      if @title_sep
        title, message = message.split(@title_sep)
        title, message = '', title if message.nil?
        title.strip!
      end

      growl(title, message, priority)
      self
    end

    # call-seq:
    #    growl_level_num( level )    => integer
    #
    # Takes the given _level_ as a string or integer and returns the
    # corresponding Growl notification level number.
    #
    def growl_level_num( level )
      level = case level
              when Integer; level
              when String; Integer(level)
              else raise ArgumentError, "unkonwn level '#{level}'" end
      if level < -2 or level > 2
        raise ArgumentError, "level '#{level}' is not in range -2..2"
      end
      level
    end

    # call-seq:
    #    growl( title, message, priority )
    #
    # Send the _message_ to the growl notifier using the given _title_ and
    # _priority_.
    #
    def growl( title, message, priority )
      message.tr!("`", "'")
      if @coalesce then coalesce(title, message, priority)
      else system @growl % [title, message, priority] end
    end

    # call-seq:
    #    coalesce( title, message, priority )
    #
    # Attempt to coalesce the given _message_ with any that might be pending
    # in the queue to send to the growl notifier. Messages are coalesced
    # with any in the queue that have the same _title_ and _priority_.
    #
    # There can be only one message in the queue, so if the _title_ and/or
    # _priority_ don't match, the message in the queue is sent immediately
    # to the growl notifier, and the current _message_ is queued.
    #
    def coalesce( *msg )
      @c_mutex.synchronize do
        if @c_queue.empty?
          @c_queue << msg
          @c_thread.run

        else
          qmsg = @c_queue.last
          if qmsg.first != msg.first or qmsg.last != msg.last
            @c_queue << msg
          else 
            qmsg[1] << "\n" << msg[1]
          end
        end
      end

      Thread.pass
    end

    # call-seq:
    #    setup_coalescing
    #
    # Setup the appender to handle coalescing of messages before sending
    # them to the growl notifier. This requires the creation of a thread and
    # mutex for passing messages from the appender thread to the growl
    # notifier thread.
    #
    def setup_coalescing
      @c_mutex = Mutex.new
      @c_queue = []

      @c_thread = Thread.new do
        Thread.stop
        loop do
          sleep 0.5
          @c_mutex.synchronize {
            system(@growl % @c_queue.shift) until @c_queue.empty?
          }
          Thread.stop if @c_queue.empty?
        end  # loop
      end  # Thread.new
    end

  end  # class Growl

end  # module Logging::Appenders

# EOF