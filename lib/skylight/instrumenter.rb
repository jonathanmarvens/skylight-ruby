module Skylight
  class Instrumenter

    # Maximum number of traces to sample for each interval
    SAMPLE_SIZE = 100

    # Time interval for each sample in seconds
    INTERVAL = 5

    def self.start!(config = Config.new)
      # Convert a hash to a config object
      if Hash === config
        config = Config.new config
      end

      new(config).start!
    end

    attr_reader :config, :worker, :samples

    def initialize(config)
      @config = config
      @worker = Worker.new(self)
    end

    def start!
      @worker.start!
      Subscriber.register!(config)

      # Ensure properly configured
      return unless config

      # Ensure that there is an API token
      unless config.authentication_token
        if logger = config.logger
          logger.warn "[SKYLIGHT] No authentication token provided; cannot start agent."
        end

        return
      end

      self
    end

    def trace(endpoint = nil)
      # If there already is a trace going on, then just continue
      if Thread.current[Trace::KEY]
        return yield
      end

      # If the request should not be sampled, yield
      unless trace = create_trace(endpoint)
        return yield
      end

      # Otherwise, setup the new trace and continue
      begin
        Thread.current[Trace::KEY] = trace
        yield(trace)
      ensure
        Thread.current[Trace::KEY] = nil

        begin
          trace.commit
          process(trace)
        rescue Exception => e
          error(e)
        end
      end
    end

  private

    def create_trace(endpoint)
      Trace.new(endpoint)
    # Paranoia
    rescue => e
      error e
      nil
    end

    def process(trace)
      debug "Submitting trace to worker"
      unless @worker.submit(trace)
        config.logger.warn("[SKYLIGHT] Could not submit trace to worker")
      end
    end

    def error(msg)
      return unless l = config.logger

      if Error == msg
        msg = "#{e.message} (#{e.class}) - #{e.backtrace && e.backtrace.first}"
      end

      l.error "[SKYLIGHT] #{msg}"
    rescue
    end

    def debug(msg)
      return unless l = config.logger
      l.debug "[SKYLIGHT] #{msg}"
    end

  end
end
