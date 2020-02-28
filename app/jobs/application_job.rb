require "logging/logs"
# Do not inherit from ActiveJob. All jobs use sidekiq
class ApplicationJob
  include Sidekiq::Worker
  include Logging::Logs

  sidekiq_options backtrace: true

private

  def set_trace_id(trace_id_passed_to_job)
    trace_id_passed_to_job ||= SecureRandom.uuid
    Thread.current.thread_variable_set(TRACE_ID, trace_id_passed_to_job)
    trace_id_passed_to_job
  end
end
