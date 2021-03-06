# encoding: utf-8

#require 'menu_extension_helper'
require 'panorama_connection'
require 'key_explanation_helper'
require 'ajax_helper'
require 'diagram_helper'
require 'html_helper'
require 'database_helper'
require 'slickgrid_helper'
require 'explain_application_info_helper'
require 'strings_helper'

# Fix uninitialized constant Application if used as engine
require_relative '../../config/engine_config'

# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
  include ExceptionHelper
  include KeyExplanationHelper
  include AjaxHelper
  include DiagramHelper
  include HtmlHelper
  include DatabaseHelper
  include SlickgridHelper
  include ExplainApplicationInfoHelper
  include StringsHelper

  include ActionView::Helpers::SanitizeHelper

  def get_client_info_store
    if !defined?($login_client_store) || $login_client_store.nil?
      $login_client_store = ActiveSupport::Cache::FileStore.new(EngineConfig.config.client_info_filename)
      Rails.logger.info("Local directory for client-info store is #{EngineConfig.config.client_info_filename}")
    end

    $login_client_store
  rescue Exception =>e
    raise "Exception '#{e.message}' while creating file store at '#{EngineConfig.config.client_info_filename}'"
  end

  # Schreiben eines client-bezogenen Wertes in serverseitigen Cache
  def write_to_client_info_store(key, value)
    cached_client_key = get_decrypted_client_key                                # ausserhalb des Exception-Handlers, da evtl. ActiveSupport::MessageVerifier::InvalidSignature bereits in get_cached_client_key gefangen wird
    if !defined?(@buffered_client_info_store) || @buffered_client_info_store.nil?  # First access after initiation of object
      @buffered_client_info_store = EngineConfig.get_client_info_store.read(cached_client_key)                 # Kompletten Hash aus Cache auslesen
    end
    @buffered_client_info_store = {} if @buffered_client_info_store.nil? || @buffered_client_info_store.class != Hash  # Neustart wenn Struktur nicht passt

    @buffered_client_info_store[key] = value                                      # Wert in Hash verankern
    begin
      EngineConfig.get_client_info_store.write(cached_client_key, @buffered_client_info_store)  # Überschreiben des kompletten Hashes im Cache
    rescue Exception =>e
      Rails.logger.error("Exception '#{e.message}' raised while writing file store at '#{EngineConfig.config.client_info_filename}'")
      raise "Exception '#{e.message}' while writing file store at '#{EngineConfig.config.client_info_filename}'"
    end
  end

  # Lesen eines client-bezogenen Wertes aus serverseitigem Cache
  # Parameter:
  #     key: Key to find
  #     default_proc: proc to kalkulate value if does not yet exists
  def read_from_client_info_store(key)
    if !defined?(@buffered_client_info_store) || @buffered_client_info_store.nil?                                           # First access after initiation of object
      @buffered_client_info_store = EngineConfig.get_client_info_store.read(get_decrypted_client_key)    # Auslesen des kompletten Hashes aus Cache
    end
    if @buffered_client_info_store.nil? || @buffered_client_info_store.class != Hash                       # Abbruch wenn Struktur nicht passt
      Rails.logger.error "read_from_client_info_store: No data found in client_info_store while looking for key=#{key}"
      return nil
    end
    @buffered_client_info_store[key]                                              # return value regardless it's nil or not
  end

  def read_from_browser_tab_client_info_store(key)
#    Rails.logger.debug "read_from_browser_tab_client_info_store: start read for key = #{key}"
    browser_tab_ids = read_from_client_info_store(:browser_tab_ids)             # read full tree with all browser-tab-specific connections
    raise "No session state available at Panorama-Server: Please restart app in browser" if browser_tab_ids.nil?
    browser_tab_ids[@browser_tab_id][key]                                       # get current value for current browser tab
  end

  def write_to_browser_tab_client_info_store(key, value)
#    Rails.logger.debug "write_from_browser_tab_client_info_store: start read for key = #{key}"
    browser_tab_ids = read_from_client_info_store(:browser_tab_ids)             # read full tree with all browser-tab-specific connections
    raise "No session state available at Panorama-Server: Please restart app in browser" if browser_tab_ids.nil?
    browser_tab_ids[@browser_tab_id][key] = value                               # set current value for current browser tab
    write_to_client_info_store(:browser_tab_ids, browser_tab_ids)               # write full tree back to store
  end

  # Setzen locale in Client_Info-Cache und aktueller Session
  def set_I18n_locale(locale)
    if !locale.nil? && ['de', 'en'].include?(locale)
      write_to_client_info_store(:locale, locale)
    else
      write_to_client_info_store(:locale, 'en')
      Rails.logger.warn(">>> I18n.locale set to 'en' because '#{locale}' is not yet supported")
    end
    @buffered_locale = nil                                                      # Sicherstellen, dass lokaler Cache neu aus FileStore gelesen wird
    I18n.locale = get_locale
  end

  # Cachen diverser Client-Einstellungen in lokalen Variablen
  def get_locale
    @buffered_locale = read_from_client_info_store(:locale) if !defined?(@buffered_locale) || @buffered_locale.nil?
    @buffered_locale
  end

  def set_current_database(current_database)
    # Transfer to Hash if it is not
    if !current_database.nil? && current_database.class != Hash
      not_hash = current_database
      current_database = {}
      not_hash.each do |key, value|
        current_database[key.to_sym] = value
      end
    end

    @buffered_current_database = nil                                            # lokalen Cache verwerfen
    current_database[:query_timeout] = current_database[:query_timeout].to_i if !current_database.nil?

    write_to_browser_tab_client_info_store(:current_database, current_database)
    set_connection_info_for_request(current_database)                           # Pin connection info for following request
  end

  def get_current_database
    @buffered_current_database = read_from_browser_tab_client_info_store(:current_database) if !defined?(@buffered_current_database) || @buffered_current_database.nil?
    @buffered_current_database
  end

  def set_cached_dbid(dbid)                                                     # Current or previous DBID of connected database
    Rails.logger.debug("ApplicationHelper.set_cached_dbid set choosen_dbid = #{dbid}")

    @buffered_dbid = nil                                                        # throe away previous value
    set_current_database(get_current_database.merge({choosen_dbid: dbid.to_i}))
    # write_to_client_info_store(:dbid, dbid.to_i)
  end

  def get_dbid    # die originale oder nach Login ausgewählte DBID
    @buffered_dbid = get_current_database[:choosen_dbid] if !defined?(@buffered_dbid) || @buffered_dbid.nil?
    @buffered_dbid
  end

  def get_db_version    # Oracle-Version
    PanoramaConnection.db_version
  end

  def set_cached_time_selection_start(time_selection_start)
    @buffered_time_selection_start = nil
    write_to_client_info_store(:time_selection_start, time_selection_start)
  end

  def get_cached_time_selection_start
    @buffered_time_selection_start = read_from_client_info_store(:time_selection_start) if !defined?(@buffered_time_selection_start) ||  @buffered_time_selection_start.nil?
    @buffered_time_selection_start
  end

  def set_cached_time_selection_end(time_selection_end)
    @buffered_time_selection_end = nil
    write_to_client_info_store(:time_selection_end, time_selection_end)
  end

  def get_cached_time_selection_end
    @buffered_time_selection_end = read_from_client_info_store(:time_selection_end) if !defined?(@buffered_time_selection_end) || @buffered_time_selection_end.nil?
    @buffered_time_selection_end
  end

  def get_cached_panorama_object_sizes_exists
    current_database = get_current_database
    if current_database[:cached_panorama_object_sizes_exists].nil?
      current_database[:cached_panorama_object_sizes_exists] = PanoramaSamplerStructureCheck.panorama_table_exists?('Panorama_Object_Sizes')
      set_current_database(current_database)                                    # write back to store
    end
    current_database[:cached_panorama_object_sizes_exists]
  end


  # Genutzt zur Anzeige im zentralen Screen
  def current_tns
    if get_current_database
      get_current_database[:tns]
    else
      '[Keine]'
    end
  end 

  def formattedNumber(number,                 # Auszugebende Zahl (Integer oder Float)
                      decimalCount=0,         # Anzahl Dezimalstellen
                      supress_0_value=false   # Unterdrücken der Ausgabe bei number=0 ?
                     )
    decimal_delimiter   = numeric_decimal_separator
    thousands_delimiter = numeric_thousands_separator
    return '' if number.nil?   # Leere Ausgabe bei nil
    number = number.to_f if number.instance_of?(String) || number.instance_of?(BigDecimal)   # Numerisches Format erzwingen
    number = number.round(decimalCount) if number.instance_of?(Float) # Ueberlauf von Stellen kompensieren

    return if supress_0_value && number == 0  # Leere Ausgabe bei Wert 0 und Unterdrückung Ausgabe angefordert

    return if number == Float::INFINITY || number.to_f.nan? # Division / 0 erlaubt in Float, bringt Infinity

    if decimalCount > 0
      decimal = number.abs-number.abs.floor  # Dezimalanteil ermitteln
      decimalCount.times do
        decimal *= 10
      end
      output = decimal_delimiter+sprintf('%.*d', decimalCount, decimal.round) # Dezimale mit Vornullen
    else
      output = '' # Keine Dezimalausgabe
    end
    stringNumber = number.abs.to_i.to_s     # mit ganzzahligem Rest weiter
    tausender = 0
    (stringNumber.length-1).downto(0) { |i|
      tausender+= 1
      if tausender > 3
        output = thousands_delimiter + output
        tausender = 1
      end
      output = stringNumber[i].chr + output 
     }
    output = '-'+output if number < 0
    output
  rescue Exception => e
    log_exception_backtrace(e, 20)
    msg = e.message
    msg << " unsupported datatype #{number.class}" if !(number.instance_of?(Float)  || number.class.name == 'Integer' || number.class.name == 'Fixnum' || number.class.name == 'Bignum')
    raise "formattedNumber: #{msg} evaluating number=#{number} (#{number.class}), decimalCount=#{decimalCount} (#{decimalCount.class}), supress_0_value=#{supress_0_value} (#{supress_0_value.class})"
  rescue
    msg = " unsupported datatype #{number.class}" if !(number.instance_of?(Float)  || number.class.name == 'Integer' || number.class.name == 'Fixnum' || number.class.name == 'Bignum')
    raise "formattedNumber: #{msg} evaluating number=#{number} (#{number.class}), decimalCount=#{decimalCount} (#{decimalCount.class}), supress_0_value=#{supress_0_value} (#{supress_0_value.class})"
  end

  alias fn formattedNumber

  # Sichere Division / 0 absichern
  def secure_div(divident, divisor)
    return nil if divisor == 0
    divident.to_f/divisor
  end


  # Zeistempel in sprach-lokaler Notation ausgeben
  def localeDateTime(timestamp, format = :seconds)
    return '' if timestamp.nil?                                                 # Leere Ausgabe, wenn nil
    timestamp = timestamp.to_datetime if timestamp.class == Time                # Sicherstellen, dass vom Typ DateTime and local timezone
    case format
      when :days    then timestamp.strftime(strftime_format_with_days)
      when :seconds then timestamp.strftime(strftime_format_with_seconds)
      when :minutes then timestamp.strftime(strftime_format_with_minutes)
    else
      raise "Unknown parameter format = #{format} in localeDateTime"
    end
  end

  # Milli-Sekunden seit 1970
  def milliSec1970(timestamp)
    timestamp.strftime('%s').to_i * 1000
  end

  # Escape single quote in Javascript strings bounded with single quotes themself
  def escape_js_single_quote(org)
    org.gsub(/'/, "'+String.fromCharCode(39)+'")
  end

  # Maskieren von html-special chars incl. NewLine
  def my_html_escape(org_value, line_feed_to_br=true)
    '' if org_value.nil?

    retval =
    ERB::Util.html_escape(org_value).   # Standard-Escape kann kein NewLine-><BR>
      gsub(/\r/, '')      # Alle vorkommenden CR ersetzen, führt sonst bei Javascript zu Error String not closed

    retval = retval.gsub(/\n/, '<br>') if line_feed_to_br  # Alle vorkommenden NewLine ersetzen
    retval
  end

  # Escape SQL-Syntax to be transform SQL-Statements for usage in EXECUTE IMMEDIATE etc. with ''
  def sql_escape(org_value)
    org_value.gsub(/'/, "''").gsub(/&/, "'||CHR(38)||'")
  end

  # Ermitteln prozentualen Anteil
  def percentage(single, sum)
    single && sum && sum != 0 ? single.to_f/sum*100 : 0
  end

  # switch empty param string to nil
  def prepare_param(param_sym)
    retval = params[param_sym]
    retval = nil if retval == ''
    retval.strip! unless retval.nil?                                            # Remove leading and trailing blanks
    retval
  end

  # Aufbereiten des Parameters "instance" aus Request, return nil wenn kein plausibler Wert
  def prepare_param_instance
    retval = params[:instance].to_i
    retval = nil if retval == 0
    write_to_client_info_store(:instance, retval)      # Werte puffern fuer spaetere Wiederverwendung
    retval
  end

  # Aufbereiten des Parameters "dbid" aus Request, return session-default wenn kein plausibler Wert
  def prepare_param_dbid
    retval = params[:dbid]
    retval = get_dbid unless retval
    retval
  end

  # Ermitteln der minimalen und maximalen Snap-ID zu gebenen Zeiten einer Instance
  # Format "DD.MM.YYYY HH:MI" bzw.sql_datetime_minute_mask (locale)
  # Belegt die Instance-Variablen @min_snap_id und @max_snap_id
  def get_instance_min_max_snap_id(time_selection_start, time_selection_end, instance)
    additional_where = ''
    additional_binds = []
    if instance && instance != 0
      additional_where << ' AND Instance_Number = ?'
      additional_binds << instance
    end

    snaps = sql_select_all ["
      SELECT /* Panorama-Tool Ramm */ Min(Snap_ID) Min_Snap_ID, MAX(Snap_ID) Max_Snap_ID
      FROM   DBA_Hist_Snapshot
      WHERE  Begin_Interval_Time >= TO_TIMESTAMP(?, '#{sql_datetime_minute_mask}')
      AND    Begin_Interval_Time <= TO_TIMESTAMP(?, '#{sql_datetime_minute_mask}')
      AND    DBID            = ?
      #{additional_where}",
                            time_selection_start, time_selection_end, prepare_param_dbid].concat(additional_binds)
    no_snaps_message = "No snapshot found between #{time_selection_start} and #{time_selection_end} for instance #{instance}"

    raise no_snaps_message if snaps.length == 0
    @min_snap_id = snaps[0].min_snap_id      # Kleinste ID
    @max_snap_id = snaps[0].max_snap_id      # Groesste ID
    raise no_snaps_message unless @min_snap_id
  end

  # Generische Methode zum Fuellen von Collections
  # liefert Array mit Results
  # Aufruf z.B.: @employees = fill_collection Employee, "[Keiner]"
  # Klasse muss id und name enthalten
  def fill_default_collection(classtype, dummy_name='[Alle]', show_id=true)
    colls = []
    dummy = classtype.new :name => dummy_name
    dummy.id = nil
    colls << dummy
    dbcolls = classtype.all :order => (show_id ? 'id' : 'name')
    dbcolls.each { |d| colls << d }
    colls
  end

  # Sichern der Parameter time_selection_start und time_selection_end in session, Prüfen auf Valides Format
  def save_session_time_selection
    def check_timestamp_picture(ts)    # Test auf struktur DD.MM.YYYY HH:MM or DD.MM.YYYY HH:MM:SS
      # Test auf Identität der Trennzeichen zwischen Maske und Prüftext
      index = 0
      sql_datetime_minute_mask.split(//).each do |m|
        unless m.count 'DMYH24I:' # Maskenzeichen an Position enthält nicht einen der Werte
          raise "#{t(:application_helper_delimiter_on_pos, :default=>'Delimiter at position')} #{index} #{t(:application_helper_is_not, :default=>'is not')} '#{m}'" if ts[index,1] != m
        end
        index = index+1
      end

      daypos = sql_datetime_minute_mask.index 'DD'
      raise "#{t(:application_helper_length_error, :default=>'Length of expression')} != 16 or 19" if ts.length != 16 && ts.length != 19                      # Minute or seconds
      raise t(:application_helper_range_error_day, :default=>'Day not between 01 and 31')        if  ts[daypos,1] < '0' || ts[daypos,1] > '3' ||      # Tag
                                                      ts[daypos+1,1] < '0' || ts[daypos+1,1] > '9' ||
                                                      ts[daypos,2].to_i < 1  ||
                                                      ts[daypos,2].to_i > 31

      monthpos = sql_datetime_minute_mask.index 'MM'
      raise t(:application_helper_range_error_month, :default=>'Month not between 01 and 12')      if ts[monthpos,1] < '0' || ts[monthpos,1] > '1' ||      # Monat
                                                     ts[monthpos+1,1] < '0' || ts[monthpos+1,1] > '9' ||
                                                     ts[monthpos,2].to_i < 1  ||
                                                     ts[monthpos,2].to_i > 12

      yearpos = sql_datetime_minute_mask.index 'YYYY'
      raise t(:application_helper_range_error_year, :default=>'Year not between 1000 and 2999') if ts[yearpos,1] < '1' || ts[yearpos,1] > '2' ||      #Jahr
                                                       ts[yearpos+1,1] < '0' || ts[yearpos+1,1] > '9' ||
                                                       ts[yearpos+2,1] < '0' || ts[yearpos+2,1] > '9' ||
                                                       ts[yearpos+3,1] < '0' || ts[yearpos+3,1] > '9'

      hourpos = sql_datetime_minute_mask.index 'HH24'
      raise t(:application_helper_range_error_hour, :default=>'Hour not between 00 and 23') if ts[hourpos,1] < '0' || ts[hourpos,1] > '2' ||    # Stunde
                                                       ts[hourpos+1,1] < '0' || ts[hourpos+1,1] > '9' ||
                                                       ts[hourpos,2].to_i > 23

      minutepos = sql_datetime_minute_mask.index('MI') - 2    # HH24 verbraucht 2 stellen mehr als in Realität
      raise t(:application_helper_range_error_minute, :default=>'Minute not between 00 and 59') if ts[minutepos,1] < '0' || ts[minutepos,1] > '5' ||    # Minute
                                                       ts[minutepos+1,1] < '0' || ts[minutepos+1,1] > '9' ||
                                                       ts[minutepos,2].to_i > 59

      if ts.length == 19                                                        # Timestamp contains seconds as last section
        second_pos = 17
        raise t(:application_helper_range_error_second, :default=>'Second not between 00 and 59') if ts[second_pos,1] < '0' || ts[second_pos,1] > '5' ||    # Second
            ts[second_pos+1,1] < '0' || ts[second_pos+1,1] > '9' ||
            ts[second_pos,2].to_i > 59
      end
      ts                                                                        # Function Return-wert
    rescue Exception => e
      raise "#{t(:application_helper_ts_invalid_format, :default=>'Invalid format of timestamp')} '#{ts}'. #{t(:application_helper_ts_expected, :default=>'Expected is')} '#{human_datetime_minute_mask}'! Problem: #{e.message}"
    end

    raise "Parameter 'time_selection_start' missing in hash 'params'" unless params[:time_selection_start]
    raise "Parameter 'time_selection_end' missing in hash 'params'"   unless params[:time_selection_end]
    @time_selection_start = params[:time_selection_start].rstrip
    @time_selection_end   = params[:time_selection_end].rstrip

    if @time_selection_start && @time_selection_start != ''
      set_cached_time_selection_start(check_timestamp_picture(@time_selection_start))
    end
    if @time_selection_end && @time_selection_end != ''
      set_cached_time_selection_end(check_timestamp_picture(@time_selection_end))
    end
  end

  # Vorbelegung fuer Eingabefeld
  def default_time_selection_start
    if get_cached_time_selection_start && get_cached_time_selection_start != ''
      get_cached_time_selection_start
    else
      "#{Date.today.strftime(strftime_format_with_days)} 00:00"
    end
  end

  # Vorbelegung fuer Eingabefeld
  def default_time_selection_end
    if get_cached_time_selection_end && get_cached_time_selection_end != ''
      get_cached_time_selection_end
    else
      "#{Date.today.strftime(strftime_format_with_days)} 13:00"
    end
  end



  # Schnell zu selektierende Information zu Wait-Event-Parametern
  def quick_wait_params_info(event, p1, p1text, p1raw, p2, p2text, p2raw, p3, p3text, p3raw)
    def get_wait_stat_class_name(id)  # Ermitteln WaitStat aus x. Position nach Class-ID
      return '' unless id
      id = id.to_i
      unless defined?(@block_classes)                                           # Klassenvariable einmalig mit Daten befüllen wenn leer
        @block_classes = {}
        sql_select_all('SELECT /* Panorama-Tool Ramm */ RowNum, class ClassName FROM v$WaitStat').each do |w|
          @block_classes[w.rownum.to_i] = w.classname
        end
      end

      addition = ''

      if id > 19  # Undo-Segemnt mit in ID
        undo_segment = ((id-15)/2).to_i  # ID = 2 * Undo-Segment + 15
        id = id - (undo_segment-1)*2 # Verbleibende ID 17, 18
        addition = "Undo-Segment=#{undo_segment}"
      end
      "Block-Class=#{id} (#{@block_classes[id]}) #{addition}"
    end


    result = nil # Default

    if (event && event.include?('gc ') || event == 'buffer busy waits'
       ) && (p3text == 'id#' || p3text == 'class#')
      class_id = case p3text
                   when 'id#' then p3 % 65536
                   when 'class#' then p3
                   else
                     nil
      end
      result = get_wait_stat_class_name(class_id)
    end
    result
  end

  # Cachen von gekürzten SQL-Texten zu SQL-ID's
  def get_cached_sql_shorttext_by_sql_id(sql_id)
    # optional Lebensdauer des Caches mit Option  :expires_in => 5.minutes setzen
    Rails.cache.fetch("SQLShortText_#{sql_id}") {get_sql_shorttext_by_sql_id(sql_id)}
  end

  # Add string to status-bar-message
  def add_statusbar_message(message)
    @statusbar_message = '' if !defined?(@statusbar_message) || @statusbar_message.nil?
    @statusbar_message << "\n" if @statusbar_message.length > 0
    @statusbar_message << message
  end


  # Rendern des Templates für Action, optionale mit Angabe des Partial-Namens wenn von Action abweicht
  # options support:
  #    :additional_javascript_string  = js-text
  #    :status_bar_message            = html-text
  #    :hide_status_bar               = true
  #    :controller                    = controller for partial

  def render_partial(partial_name = nil, options = {})
    raise "render_partial: options should of class Hash, not #{options.class}" unless options.class == Hash

    partial_name = self.action_name if partial_name.nil?
    render_internal(params[:update_area], controller_name, partial_name, options)
  end

  # Eigentliche Durchführung des renderns, auch genutzt von env_controller.render_menu_action
  def render_internal(update_area, controller, partial, options = {})
    raise "render_internal: options should of class Hash, not #{options.class}" unless options.class == Hash

    if defined?(@statusbar_message) && !@statusbar_message.nil? && @statusbar_message.length > 0
      if options[:status_bar_message]
        options[:status_bar_message] = "#{options[:status_bar_message]}\n#{my_html_escape(@statusbar_message)}"
      else
        options[:status_bar_message] = my_html_escape(@statusbar_message)
      end
    end

    additional_javascript_string = options[:additional_javascript_string]
    additional_javascript_string = "hide_status_bar(); #{additional_javascript_string}" if options[:hide_status_bar]
    additional_javascript_string = "show_status_bar_message('#{options[:status_bar_message]}'); #{additional_javascript_string}" if options[:status_bar_message]

    respond_to do |format|
      format.js {
        raise "render_internal js should not be called"
        #render :js => "$('##{update_area}').html('#{escape_javascript(render_to_string :partial=>"#{controller}/#{partial}")
        #
        #                                                         .gsub(/§SINGLE_QUOTE§/, "#{92.chr}#{92.chr}#{92.chr}#{92.chr}x27")
        #                                                    }'); #{additional_javascript_string}"
      }
      format.html {
        partial_controller_name = options[:controller] ? options[:controller] : controller

        if additional_javascript_string.nil?
          render(:partial=>"#{partial_controller_name}/#{partial}")                          # don't store rendered document as string
        else
          rendered_document = render_to_string :partial=>"#{partial_controller_name}/#{partial}"
          rendered_document << "<script type='text/javascript'>#{additional_javascript_string}</script>".html_safe
          render :html => rendered_document
        end
      }
    end
  end

#  # Rücksetzen des Zählers bei Neuanmeldung
#  def initialize_unique_area_id
#    write_to_client_info_store(:request_counter, 0)
#  end

  # Eindeutigen Bezeichner fuer DIV-ID in html-Struktur
  @@unique_area_id_mutex = Mutex.new                                            # Ensure that parallel requests get unique identifier

  def get_unique_area_id
    @@unique_area_id_mutex.synchronize do
      request_counter = read_from_client_info_store(:request_counter)
      request_counter = 0 if request_counter.nil? || request_counter > 1000000  # Sicherstellen, das keine Kumulation ohne Ende
      request_counter += 1                                                      # Eindeutigkeit sicherstellen durch Weiterzählen auch innerhalb eines Requests
      write_to_client_info_store(:request_counter, request_counter)
      "a#{request_counter}"
    end
  end


  # Umwandeln des String so, dass er bei Darstellung in html auch an Kommas umgebrochen werden kann
  def convert_word_wrap_comma(origin)
    # Erst alle html-Fehlinterpretationen in origin esacapen, dann MiniSpace einfuegen und html_safe setzen, damit nächster Escape durch <%= nicht mehr stattfindet
    my_html_escape(origin).gsub(/,/, ',<wbr>').html_safe    # Komma erweitert um Space mit breite 0, an dem bei word_wrap: brake_word trotzdem umgebrochen werden soll
    #my_html_escape(origin).gsub(/,/, ',&#8203;').html_safe    # Komma erweitert um Space mit breite 0, an dem bei word_wrap: brake_word trotzdem umgebrochen werden soll
  end

  # Alias-Bezeichnung für Alle in Combobox
  def all_dropdown_selector_name
    "[ #{t(:all, :default=>'All')} ]"
  end

  # Ausgabe des Textes auf Panel
  def render_yellow_pre(text, max_height = nil)
    div_id = get_unique_area_id

    output = "<div id=\"#{div_id}\">#{my_html_escape(text).html_safe}</div>
              <script type=\"text/javascript\">
                render_yellow_pre(\"#{div_id}\"#{max_height.nil? ? '' : ", #{max_height}"});
              </script>
    ".html_safe
  end

  # request parameter for later recreation of view
  # as arry entry for render_page_caption
  # May not contain '
  def get_recall_params_info_for_render_page_caption
    {
        :name =>       :recall_params_info,
        :caption =>    t(:addition_copy_recall_params_caption, :default=>'Copy request parameters to clipboard'),
        :hint =>       t(:addition_copy_recall_params_hint, :default=>"Copy request parameter to clipboard which allows you to reconstruct/replay this page later\nCall menu 'Spec. additions / Execute with given parameters' and paste this info to reconstruct your page at later time."),
        :icon_class => 'cui-copy',
        :action =>     "copy_to_clipboard('#{request.parameters.except(:update_area, :browser_tab_id)}');  alert('#{t(:addition_copy_recall_params_answer, :default=>"Current request parameters are copied to clipboard.\nUse menu \"Spec. additions / Execute with given parameters\" to paste this parameters").sub("\n", '\\n')}');"
    }
  end

  # Accessed by PanoramaConnection within request
  def set_connection_info_for_request(current_database)
    PanoramaConnection.set_connection_info_for_request(current_database.merge(
        :client_salt              => cookies['client_salt'],
        :current_controller_name  => controller_name,
        :current_action_name      => action_name
    ))
  end

  # Helper fuer Ausführung SQL-Select-Query,
  # Parameter: sql = String mit Statement oder Array mit Statement und Bindevariablen
  #            modifier = proc für Anwendung auf die fertige Row
  # return Array of Hash mit Columns des Records
  def sql_select_all(sql, modifier=nil, query_name = 'sql_select_all')   # Parameter String mit SQL oder Array mit SQL und Bindevariablen
    PanoramaConnection.sql_select_all(sql, modifier, query_name)
  end

  # Analog sql_select all, jedoch return ResultIterator mit each-Method
  # liefert Objekt zur späteren Iteration per each, erst dann wird SQL-Select ausgeführt (jedesmal erneut)
  # Parameter: sql = String mit Statement oder Array mit Statement und Bindevariablen
  #            modifier = proc für Anwendung auf die fertige Row
  def sql_select_iterator(sql, modifier=nil, query_name = 'sql_select_iterator')
    PanoramaConnection.sql_select_iterator(sql, modifier, query_name)
  end

  # Select genau erste Zeile
  def sql_select_first_row(sql, query_name = 'sql_select_first_row')
    PanoramaConnection.sql_select_first_row(sql, query_name)
  end

  # Select genau einen Wert der ersten Zeile des Result
  def sql_select_one(sql, query_name = 'sql_select_one')
    PanoramaConnection.sql_select_one(sql, query_name)
  end

  # Is database a container DB?
  def is_cdb?
    get_current_database[:cdb]
  end

  # Switch between DBA_xxx and CDB_xxx for CDBs
  def dba_or_cdb(tablename)
    if is_cdb?
      tablename.gsub(/^DBA/i, "CDB")
    else
      tablename
    end
  end

  ####################################### only protected and private methods from here #####################################
  protected
  def get_sga_sql_statement(instance, sql_id)  # Ermittlung formatierter SQL-Text

    def get_sga_sql_statement_internal(instance, sql_id)
      statement = sql_select_one(["\
        SELECT /* Panorama-Tool Ramm */ SQL_FullText
        FROM   GV$SQLArea
        WHERE  SQL_ID  = ?
        AND    Inst_ID = ?
        ",
                                  sql_id, instance, sql_id, instance
                                 ])
      statement
    end

    raise 'Parameter instance should not be nil' unless instance
    raise 'Parameter sql_id should not be nil' unless sql_id

    sql_statement = get_sga_sql_statement_internal(instance, sql_id)
    if sql_statement == '' # Nichts gefunden
      instances = sql_select_all 'SELECT Inst_ID FROM GV$Instance'
      instances.each do |i|
        if sql_statement == '' # Auf anderer Instance suchen, solange nicht gefunden
          sql_statement = get_sga_sql_statement_internal(i.inst_id, sql_id)
          sql_statement = "[Instance=#{i.inst_id}] #{sql_statement}" unless sql_statement == '' # abweichende Instance mit in Text aufnehmen
        end
      end
    end
    sql_statement
  end


  ######################################## only private methods from here ######################################
  private
  # Ermitteln Kurztext per DB aus SQL-ID
  def get_sql_shorttext_by_sql_id(sql_id)
    # erster Versuch direkt aus SGA zu lesen
    sql_text = sql_select_first_row ["\
                 SELECT /*+ Panorama-Tool Ramm */ SUBSTR(SQL_FullText, 1, 150) SQL_Text
                 FROM   gv$SQLArea
                 WHERE  SQL_ID = ?",
                           sql_id]

    if sql_text.nil? && PanoramaConnection.get_threadlocal_config[:management_pack_license] != :none  # Wenn nicht gefunden, dann in AWR-History suchen, but only if access is allowed
      sql_text = sql_select_first_row ["\
                   SELECT /*+ Panorama-Tool Ramm */ SUBSTR(SQL_Text, 1, 150) SQL_Text
                   FROM   DBA_Hist_SQLText
                   WHERE  DBID   = ?
                   AND    SQL_ID = ?",
                             get_dbid, sql_id]
    end

    if sql_text.nil?
      "< No SQL-text found for SQL-ID='#{sql_id}' >"
    else
      sql_text.sql_text
    end
  end # get_sql_shorttext_by_sql_id

  # Ausliefern des client-Keys
  def get_decrypted_client_key
    if !defined?(@buffered_client_key) || @buffered_client_key.nil?
#      Rails.logger.debug "get_decrypted_client_key: client_key = #{cookies['client_key']} client_salt = #{cookies['client_salt']}"
      return nil if cookies['client_key'].nil? && cookies['client_salt'].nil?  # Connect vom Job oder monitor
      @buffered_client_key = Encryption.decrypt_value(cookies['client_key'], cookies['client_salt'])      # wirft ActiveSupport::MessageVerifier::InvalidSignature wenn cookies['client_key'] == nil
    end
    @buffered_client_key
  rescue ActiveSupport::MessageVerifier::InvalidSignature => e
    Rails.logger.error("Exception '#{e.message}' raised while decrypting cookies['client_key'] (#{cookies['client_key']})")
    #log_exception_backtrace(e, 20)
    if cookies['client_key'].nil?
      raise("Your browser does not allow cookies for this URL!\nPlease enable usage of browser cookies for this URL and reload the page.")
    else
      cookies.delete('client_key')                                               # Verwerfen des nicht entschlüsselbaren Cookies
      cookies.delete('client_salt')
      raise "Exception '#{e.message}' while decrypting your client key from browser cookie. \nPlease try again."
    end
  end

  # Ermitteln der Min- und Max-Abgrenzungen auf Basis Snap_ID für Zeitraum über alle Instanzen hinweg
  def get_min_max_snap_ids(time_selection_start, time_selection_end, dbid)
    @min_snap_id = sql_select_one ["SELECT /*+ Panorama-Tool Ramm */ MIN(Snap_ID)
                                    FROM   (SELECT MAX(Snap_ID) Snap_ID
                                            FROM   DBA_Hist_Snapshot
                                            WHERE DBID = ?
                                            AND Begin_Interval_Time <= TO_DATE(?, '#{sql_datetime_mask(time_selection_start)}')
                                            GROUP BY Instance_Number
                                           )
                                   ", dbid, time_selection_start
                                  ]
    unless @min_snap_id   # Start vor Beginn der Aufzeichnungen, dann kleinste existierende Snap-ID
      @min_snap_id = sql_select_one ['SELECT /*+ Panorama-Tool Ramm */ MIN(Snap_ID)
                                      FROM   DBA_Hist_Snapshot
                                      WHERE DBID = ?
                                     ', dbid
                                    ]
    end

    @max_snap_id = sql_select_one ["SELECT /*+ Panorama-Tool Ramm */ MAX(Snap_ID)
                                    FROM   (SELECT MIN(Snap_ID) Snap_ID
                                            FROM   DBA_Hist_Snapshot
                                            WHERE DBID = ?
                                            AND End_Interval_Time >= TO_DATE(?, '#{sql_datetime_mask(time_selection_end)}')
                                            GROUP BY Instance_Number
                                          )
                                   ", dbid, time_selection_end
                                  ]
    unless @max_snap_id       # Letzten bekannten Snapshot werten, wenn End-Zeitpunkt in der Zukunft liegt
      @max_snap_id = sql_select_one ['SELECT /*+ Panorama-Tool Ramm */ MAX(Snap_ID)
                                      FROM   DBA_Hist_Snapshot
                                      WHERE DBID = ?
                                     ', dbid
                                    ]
    end
  end

end
