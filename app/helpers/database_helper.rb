# encoding: utf-8

# Hilfsmethoden mit Bezug auf die aktuell verbundene Datenbank sowie verbundene Einstellunen wie Sprache
module DatabaseHelper

  private
  def get_salted_encryption_key
    #"#{cookies['client_salt']}#{Rails.application.config.secret_key_base}"
    "#{cookies['client_salt']}#{Rails.application.secrets.secret_key_base}"       # Position of key after siwtch to config/secrets.yml
  end

  public
  # Client-spezifisches Verschlüsseln eines Wertes, Teil des Schlüssels liegt client-spezifisch als verschlüsselter cookie im Browser des Clients
  def database_helper_encrypt_value(raw_value)
    crypt = ActiveSupport::MessageEncryptor.new(get_salted_encryption_key)
    crypt.encrypt_and_sign(raw_value)
  end

  # Client-spezifisches Entschlüsseln des Wertes,  Teil des Schlüssels liegt client-spezifisch als verschlüsselter cookie im Browser des Clients
  def database_helper_decrypt_value(encrypted_value)
    crypt = ActiveSupport::MessageEncryptor.new(get_salted_encryption_key)
    crypt.decrypt_and_verify(encrypted_value)
  end

private
  # Notation für Connect per JRuby
  def jdbc_thin_url
    current_database = read_from_client_info_store(:current_database)
    raise 'No current DB connect info set! Please reconnect to DB!' unless current_database
    "jdbc:oracle:thin:@#{current_database[:tns]}"
  end

public

  def open_oracle_connection
    current_database = read_from_client_info_store(:current_database)

    # Unterscheiden der DB-Adapter zwischen Ruby und JRuby
    if defined?(RUBY_ENGINE) && RUBY_ENGINE == "jruby"

      begin
        config = ConnectionHolder.connection.instance_variable_get(:@config)  # Aktuelle config, kann reduziert sein auf :adapter bei NullDB
      rescue Exception => e
        Rails.logger.warn "Error: ConnectionHolder.connection.instance_variable_get(:@config): #{e.message}"
        Rails.logger.warn "Resetting connection to dummy"
        set_dummy_db_connection
        config = {}
      end
      # Connect nur ausführen wenn bisherige DB-Connection nicht der gewünschten entspricht
      if ConnectionHolder.connection.class.name != 'ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter' ||
          config[:adapter]  != 'oracle_enhanced' ||
          config[:driver]   != 'oracle.jdbc.driver.OracleDriver' ||
          config[:url]      != jdbc_thin_url ||
          config[:username] != get_current_database[:user]

        # Entschlüsseln des Passwortes
        begin
          local_password = database_helper_decrypt_value(get_current_database[:password])
        rescue Exception => e
          Rails.logger.warn "Error in open_oracle_connection decrypting pasword: #{e.message}"
          raise "One part of encryption key for stored password has changed at server side! Please connect giving username and password."
        end
        ConnectionHolder.establish_connection(
            :adapter  => "oracle_enhanced",
            :driver   => "oracle.jdbc.driver.OracleDriver",
            :url      => jdbc_thin_url,
            :username => get_current_database[:user],
            :password => local_password,
            :privilege => get_current_database[:privilege],
            :cursor_sharing => :exact             # oracle_enhanced_adapter setzt cursor_sharing per Default auf force
        )
        Rails.logger.info "Connecting database: URL='#{jdbc_thin_url}' User='#{get_current_database[:user]}'"
      else
        Rails.logger.info "Using already connected database: URL='#{jdbc_thin_url}' User='#{get_current_database[:user]}'"
      end

    else
      raise "Native ruby (RUBY_ENGINE=#{RUBY_ENGINE}) is no longer supported! Please use JRuby runtime environment! Call contact for support request if needed."
    end

    # No exception handling at this time because connection problems are raised at first access
  end

  # Format für JQuery-UI Plugin DateTimePicker
  def timepicker_dateformat
    case get_locale
      when "de" then "dd.mm.yy"
      when "en" then "yy-mm-dd"
      else "dd.mm.yy"
    end
  end

  # Maske für Date/Time-Konvertierung per strftime bis auf Tag
  def strftime_format_with_days
    case get_locale
      when "de" then "%d.%m.%Y"
      when "en" then "%Y-%m-%d"
      else "%d.%m.%Y"
    end
  end

  # Maske für Date/Time-Konvertierung per strftime bis auf sekunden
  def strftime_format_with_seconds
    case get_locale
      when "de" then "%d.%m.%Y %H:%M:%S"
      when "en" then "%Y-%m-%d %H:%M:%S"
      else "%d.%m.%Y %H:%M:%S"
    end
  end

  # Maske für Date/Time-Konvertierung per strftime bis auf Minuten
  def strftime_format_with_minutes
    case get_locale
      when "de" then "%d.%m.%Y %H:%M"
      when "en" then "%Y-%m-%d %H:%M"
      else "%d.%m.%Y %H:%M"     # Deutsche Variante als default
    end
  end

  # Ersetzung in TO_CHAR / TO_DATE in SQL
  def sql_datetime_second_mask
    case get_locale
      when "de" then "DD.MM.YYYY HH24:MI:SS"
      when "en" then "YYYY-MM-DD HH24:MI:SS"
      else "DD.MM.YYYY HH24:MI:SS" # Deutsche Variante als default
    end
  end

  # Ersetzung in TO_CHAR / TO_DATE in SQL
  def sql_datetime_minute_mask
    case get_locale
      when "de" then "DD.MM.YYYY HH24:MI"
      when "en" then "YYYY-MM-DD HH24:MI"
      else "DD.MM.YYYY HH24:MI" # Deutsche Variante als default
    end
  end

    # Ersetzung in TO_CHAR / TO_DATE in SQL
  def sql_datetime_date_mask
    case get_locale
      when "de" then "DD.MM.YYYY"
      when "en" then "YYYY-MM-DD"
      else "DD.MM.YYYY" # Deutsche Variante als default
    end
  end

  # Entscheiden auf Grund der Länge der Eingabe, welche Maske hier zu verwenden ist
  def sql_datetime_mask(datetime_string)
    return "sql_datetime_mask: Parameter=nil" if datetime_string.nil?           # Maske nicht verwendbar
    datetime_string.strip!                                                      # remove leading and trailing blanks
    case datetime_string.length
      when 10 then sql_datetime_date_mask
      when 16 then sql_datetime_minute_mask
      when 19 then sql_datetime_second_mask
      else
        raise "sql_datetime_mask: No SQL datetime mask found for '#{datetime_string}'"
    end

  end

  # Menschenlesbare Ausgabe in Hints etc
  def human_datetime_minute_mask
    case get_locale
      when "de" then "TT.MM.JJJJ HH:MI"
      when "en" then "YYYY-MM-DD HH:MI"
      else "TT.MM.JJJJ HH:MI" # Deutsche Variante als default
    end
  end

  # Menschenlesbare Ausgabe in Hints etc
  def human_datetime_day_mask
    case get_locale
      when "de" then "TT.MM.JJJJ"
      when "en" then "YYYY-MM-DD"
      else "TT.MM.JJJJ" # Deutsche Variante als default
    end
  end


  def numeric_thousands_separator
    case get_locale
      when "de" then "."
      when "en" then ","
      else "." # Deutsche Variante als default
    end
  end


  def numeric_decimal_separator
    case get_locale
      when "de" then ","
      when "en" then "."
      else "," # Deutsche Variante als default
    end
  end


end