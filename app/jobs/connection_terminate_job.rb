class ConnectionTerminateJob < ApplicationJob
  include ExceptionHelper

  queue_as :default

  CHECK_CYCLE_SECONDS = 3600                                                    # Terminate idle sessions with last active older than 60 minutes

  def perform(*args)
    ConnectionTerminateJob.set(wait_until: Time.now.round + CHECK_CYCLE_SECONDS).perform_later  # Schedule next start
    Thread.new{PanoramaConnection.disconnect_aged_connections(CHECK_CYCLE_SECONDS)}
  rescue Exception => e
    Rails.logger.error "Exception in ConnectionTerminateJob.perform:\n#{e.message}"
    log_exception_backtrace(e, 40)
    raise e
  end
end
