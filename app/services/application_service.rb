require "logging/logs"
class ApplicationService
  include Logging::Logs

  def trace_id(generate_if_blank: true)
    id = Thread.current.thread_variable_get(TRACE_ID)
    if id.blank? && generate_if_blank
      id = SecureRandom.uuid
      Thread.current.thread_variable_set(TRACE_ID, id)
    end
    id
  end

end
