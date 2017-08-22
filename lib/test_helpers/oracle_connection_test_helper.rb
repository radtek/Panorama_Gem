# requires config/environment.rb loaded a'la: require File.expand_path("../../test/dummy/config/environment.rb", __FILE__)
require 'encryption'

class ActiveSupport::TestCase
  include ApplicationHelper
  include EnvHelper
  include ActionView::Helpers::TranslationHelper

  # Setup all fixtures in test/fixtures/*.(yml|csv) for all tests in alphabetical order.
  #
  # Note: You'll currently still have to declare fixtures explicitly in integration tests
  # -- they do not yet inherit this setting
  fixtures :all

  # Add more helper methods to be used by all tests here...

  # Sicherstellen, dass immer auf ein aktuelles Sessin-Objekt zurückgegriffern werden kann
  def session
    @session
  end

  def controller_name                                                           # Dummy to fulfill requirements of set_connection_info_for_request
    'oracle_connection_test_helper.rb'
  end

  def action_name                                                               # Dummy to fulfill requirements of set_connection_info_for_request
    'Test'
  end

  #def cookies
  #  {:client_key => 100 }
  #end

  def create_prepared_database_config(test_config)
    db_config = {}
    test_url = test_config['test_url'].split(":")
    db_config[:modus]        = 'host'

    db_config[:host]         = test_url[3].delete "@"
    if test_url[4]['/']                                                         # Service_Name
      db_config[:port]       = test_url[4].split('/')[0]
      db_config[:sid]        = test_url[4].split('/')[1]

      db_config[:sid_usage]  = :SERVICE_NAME
    else                                                                        # SID
      db_config[:port]       = test_url[4]
      db_config[:sid]        = test_url[5]
      db_config[:sid_usage]  = :SID
    end

    db_config[:user]         = test_config["test_username"]
    db_config[:tns]          = test_config['test_url'].split('@')[1]     # Alles nach jdbc:oracle:thin@

    if ENV['MANAGEMENT_PACK_LICENCSE']
      raise "Wrong environment value MANAGEMENT_PACK_LICENCSE=#{ENV['MANAGEMENT_PACK_LICENCSE']}" if !['diagnostics_pack', 'diagnostics_and_tuning_pack', 'none'].include?(ENV['MANAGEMENT_PACK_LICENCSE'])
      db_config[:management_pack_license] = ENV['MANAGEMENT_PACK_LICENCSE'].to_sym
    else
      db_config[:management_pack_license] = :diagnostics_and_tuning_pack  # Allow access on management packs, Default if nothing else specified
    end

    db_config
  end

  # Method shared with Panorama children
  def connect_oracle_db_internal(test_config)
    current_database = create_prepared_database_config(test_config)

    # Config im Cachestore ablegen
    # Sicherstellen, dass ApplicationHelper.get_cached_client_key nicht erneut den client_key entschlüsseln will
    initialize_client_key_cookie

    # Passwort verschlüsseln in session
    current_database[:password] = Encryption.encrypt_value(test_config["test_password"], cookies['client_salt'])
    write_to_client_info_store(:current_database, current_database)


    # puts "Test for #{ENV['DB_VERSION']} with #{database.user}/#{database.password}@#{database.host}:#{database.port}:#{database.sid}"
    # TODO Sollte so nicht mehr notwendig sein
    #open_oracle_connection                                                      # Connection zur Test-DB aufbauen, um Parameter auszulesen
    set_connection_info_for_request(current_database)

    # DBID is set at first request after login normally
    set_cached_dbid(PanoramaConnection.dbid)

    set_I18n_locale('de')
  end

  def set_session_test_db_context
    Rails.logger.info ""
    Rails.logger.info "=========== test_helper.rb : set_session_test_db_context ==========="

    # Client Info store entfernen, da dieser mit anderem Schlüssel verschlüsselt sein kann
    #FileUtils.rm_rf(Application.config.client_info_filename)

    #initialize_client_key_cookie                                                # Ensure browser cookie for client_key exists

    # 2017/07/26 cookies are reset in ActionDispatch::IntegrationTest if using initialize_client_key_cookie
    cookies['client_salt'] = 100
    cookies['client_key']  = Encryption.encrypt_value(100, cookies['client_salt'])

    connect_oracle_db
    sql_row = sql_select_first_row "SELECT SQL_ID, Child_Number, Parsing_Schema_Name FROM v$sql WHERE SQL_ID IN (SELECT SQL_ID from v$sql_plan WHERE Object_Name = 'OBJ$') AND Object_Status = 'VALID' ORDER BY Executions DESC"
    @sga_sql_id = sql_row.sql_id
    @sga_child_number = sql_row.child_number
    @sga_parsing_schema_name = sql_row.parsing_schema_name
    db_session = sql_select_first_row "select Inst_ID, SID, Serial# SerialNo, RawToHex(Saddr)Saddr FROM gV$Session s WHERE SID=UserEnv('SID')  AND Inst_ID = USERENV('INSTANCE')"
    @instance = db_session.inst_id
    @sid      = db_session.sid
    @serialno = db_session.serialno
    @saddr    = db_session.saddr

    yield   # Ausführen optionaler Blöcke mit Anweisungen, die gegen die Oracle-Connection verarbeitet werden

    # Rückstellen auf NullDB kann man sich hier sparen
  end
end
