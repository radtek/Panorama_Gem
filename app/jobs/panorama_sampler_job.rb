class PanoramaSamplerJob < ApplicationJob
  include ExceptionHelper

  queue_as :default

  SECONDS_LATE_ALLOWED = 3                                                      # x seconds delay after job creation are accepted

  def perform(*args)

    snapshot_time = Time.now.round                                              # cut subseconds

    min_snapshot_cycle = PanoramaSamplerConfig.min_snapshot_cycle

    # calculate next snapshot time from now
    last_snapshot_minute = snapshot_time.min-snapshot_time.min % min_snapshot_cycle
    last_snapshot_time = Time.new(snapshot_time.year, snapshot_time.month, snapshot_time.day, snapshot_time.hour, last_snapshot_minute, 0)
    next_snapshot_time = last_snapshot_time + min_snapshot_cycle * 60
    PanoramaSamplerJob.set(wait_until: next_snapshot_time).perform_later

    if last_snapshot_time < snapshot_time-SECONDS_LATE_ALLOWED                  # Filter first Job execution at server startup, 2 seconds delay are allowed
      Rails.logger.info "#{snapshot_time}: Job suspended because not started at exact snapshot time #{last_snapshot_time}"
      return
    end

    # Iterate over PanoramaSampler entries
    PanoramaSamplerConfig.get_cloned_config_array.each do |config|
      if config[:active]

        # Call AWR / ASH function
        if config[:awr_ash_active] && (snapshot_time.min % config[:snapshot_cycle] == 0  ||  # exact startup time at full hour + x*snapshot_cycle
            snapshot_time.min == 0 && snapshot_time.hour % config[:snapshot_cycle]/60 == 0)  # Full hour for snapshot cycle = n*hour
          if  config[:last_snapshot_start].nil? || (config[:last_snapshot_start]+(config[:snapshot_cycle]).minutes <= snapshot_time+SECONDS_LATE_ALLOWED)  # snapshot_cycle expired ?, 2 seconds delay are allowed
            PanoramaSamplerConfig.modify_config_entry({id: config[:id], last_snapshot_start: snapshot_time})
            WorkerThread.create_snapshot(config, snapshot_time)
          else
            Rails.logger.error "#{Time.now}: Last snapshot start (#{config[:last_snapshot_start]}) not old enough to expire next snapshot after #{config[:snapshot_cycle]} minutes for ID=#{config[:id]} '#{config[:name]}'"
            Rails.logger.error "May be sampling is done by multiple Panorama instances?"
          end
        end

        # Sample object sizes
        if config[:object_size_active] && snapshot_time.min == 0 && (snapshot_time.hour % config[:object_size_snapshot_cycle] == 0)     # Full hour and snapshot cycle = n*hour
          if config[:last_object_size_snapshot_start].nil? || config[:last_object_size_snapshot_start].day != snapshot_time.day || config[:last_object_size_snapshot_start].hour != snapshot_time.hour
            PanoramaSamplerConfig.modify_config_entry({id: config[:id], last_object_size_snapshot_start: snapshot_time})
            WorkerThread.create_object_size_snapshot(config, snapshot_time)
          else
            Rails.logger.error "#{Time.now}: Last object size snapshot start (#{config[:last_object_size_snapshot_start]}) not old enough to expire next snapshot after #{config[:object_size_snapshot_cycle]} hours for ID=#{config[:id]} '#{config[:name]}'"
            Rails.logger.error "May be sampling is done by multiple Panorama instances?"
          end
        end

      end
    end
  rescue Exception => e
    Rails.logger.error "Exception in PanoramaSamplerJob.perform:\n#{e.message}"
    log_exception_backtrace(e, 40)
    raise e
  end
end
