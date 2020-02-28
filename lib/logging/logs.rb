module Logging
  module Logs
    TRACE_ID = "trace_id"
    def log(method, message)
      trace_id = Thread.current.thread_variable_get(TRACE_ID)
      Rails.logger.info("[Logging::Logs]#{format_trace_id(trace_id)}#{self.class}##{method}: #{message}")
    end

  private
    def format_trace_id(trace_id)
      return nil if trace_id.blank?
      " trace_id:#{trace_id} "
    end
  end
end
