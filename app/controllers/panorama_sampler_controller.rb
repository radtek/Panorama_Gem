class PanoramaSamplerController < ApplicationController
  def show_config
    if read_from_client_info_store(:encrypted_panorama_sampler_master_password)
      list_config
    else
      request_master_password
    end
  end

  def list_config
    @sampler_config = PanoramaSamplerConfig.get_cloned_config_array
    render_partial :list_config
  end

  def request_master_password
    render_partial :request_master_password
  end

  $master_password_wrong_count=0
  def check_master_password
    if params[:master_password] == EngineConfig.config.panorama_sampler_master_password
      $master_password_wrong_count=0                                            # reset delay for wrong password
      list_config
    else
      sleep $master_password_wrong_count
      $master_password_wrong_count += 1
      show_popup_message('Wrong value entered for master password')
    end
  end

  def show_new_config_form
    @modus = :new
    @config = {:id => PanoramaSamplerConfig.get_max_id+1, :snapshot_retention => 60}
    render_partial :edit_config
  end

  def show_edit_config_form
    @modus = :edit
    @config = PanoramaSamplerConfig.get_cloned_config_entry(params[:id].to_i)
    @config[:password] = nil                                                    # Password set ony if changed
    render_partial :edit_config
  end

  def save_config
    if params[:commit] == 'Save'
      store_config
    else
      check_connection
    end
  end

  def check_connection
    config_entry        = params[:config].to_unsafe_h.symbolize_keys
    config_entry[:id]   = params[:id].to_i

    org_entry = PanoramaSamplerConfig.get_cloned_config_entry(config_entry[:id])
    if org_entry.nil?                                                           # entry not yet saved
      org_entry = PanoramaSamplerConfig.prepare_saved_entry(config_entry)
    else                                                                        # entry already exists
      org_entry.merge!(PanoramaSamplerConfig.prepare_saved_entry(config_entry))
    end

    dbid = WorkerThread.check_connection(org_entry)
    if dbid.nil?
      show_popup_message('Connect not successful, see Panorama-Log for details')
    else
      add_statusbar_message('Connect successful')
      store_config                                                              # add or modify entry in persistence
    end
  end

  def store_config
    config_entry      = params[:config].to_unsafe_h.symbolize_keys
    config_entry[:id] = params[:id].to_i

    if params[:modus] == 'new'
      PanoramaSamplerConfig.add_config_entry(config_entry)
    end
    if params[:modus] == 'edit'
      PanoramaSamplerConfig.modify_config_entry(config_entry)
    end
    list_config
  end

  def delete_config
    PanoramaSamplerConfig.delete_config_entry(params[:id])
    list_config
  end
end
