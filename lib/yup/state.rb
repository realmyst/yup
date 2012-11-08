begin
  require 'bdb'
  require 'bdb/database'
rescue LoadError
  puts "Install bdb gem to use a persistent queue."
end

require "timeout"

module Yup
  class State
    RE_LEN = 1000

    attr_reader :queue

    def self.repair_if_need(path)
      env = Bdb::Env.new(0)
      env.open(path, Bdb::DB_CREATE | Bdb::DB_INIT_TXN | Bdb::DB_RECOVER, 0)
      env.close()
    end

    def initialize(path, name, feedback_channel)
      @path = path
      @name = name
      @feedback_channel = feedback_channel

      @logger = Yup.logger.clone
      @logger.progname = "Yup::State"

      FileUtils.mkdir_p(@path)
      @env   = Bdb::Env.new(0)
      @env   = @env.open(@path, Bdb::DB_CREATE | Bdb::DB_INIT_MPOOL | Bdb::DB_INIT_CDB, 0)
      @queue = @env.db
      @queue.re_len = RE_LEN
      @queue.open(nil, @name, nil, Bdb::Db::QUEUE, Bdb::DB_CREATE, 0)
    end

    def push(data)
      @logger.debug { "Push: #{data}" }
      i = 0
      until (chunk = data.slice(i, RE_LEN)).nil?
        @queue.put(nil, "", chunk, Bdb::DB_APPEND)
        i += @queue.re_len
      end
    end

    def bpop
      data = @queue.get(nil, "", nil, Bdb::DB_CONSUME_WAIT)
      @logger.debug { "Bpoped: #{data.strip}" }
      data
    end

    def to_feedback(data)
      @logger.debug { "Push to the feedback channel: #{data.strip}" }
      sock = UNIXSocket.new(@feedback_channel)
      sock.send(data, 0)
      sock.close
    end

    def close
      @queue.close(0)
    end
  end
end
