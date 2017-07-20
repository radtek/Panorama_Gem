# hold open SQL-Cursor and iterate over SQL-result without storing whole result in Array
# Peter Ramm, 02.03.2016

require 'active_record/connection_adapters/abstract_adapter'
require 'active_record/connection_adapters/oracle_enhanced/connection'
require 'active_record/connection_adapters/oracle_enhanced_adapter'
require 'active_record/connection_adapters/oracle_enhanced/quoting'
require 'encryption'

# Helper-class to allow usage of method "type_cast"
class TypeMapper < ActiveRecord::ConnectionAdapters::AbstractAdapter
    include ActiveRecord::ConnectionAdapters::OracleEnhanced::Quoting
  def initialize                                                                # fake parameter "connection"
    super('Dummy')
  end
end

# expand class by getter to allow access on internal variable @raw_statement
ActiveRecord::ConnectionAdapters::OracleEnhancedJDBCConnection::Cursor.class_eval do
  def get_raw_statement
    @raw_statement
  end
end

# Class extension by Module-Declaration : module ActiveRecord, module ConnectionAdapters, module OracleEnhancedDatabaseStatements
# does not work as Engine with Winstone application server, therefore hard manipulation of class ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
# and extension with method iterate_query

ActiveRecord::ConnectionAdapters::OracleEnhancedJDBCConnection.class_eval do

  def log(sql, name = "SQL", binds = [], statement_name = nil)
    ActiveSupport::Notifications.instrumenter.instrument(
        "sql.active_record",
        :sql            => sql,
        :name           => name,
        :connection_id  => object_id,
        :statement_name => statement_name,
        :binds          => binds) { yield }
  end

  # Method comparable with ActiveRecord::ConnectionAdapters::OracleEnhancedDatabaseStatements.exec_query,
  # but without storing whole result in memory
  def iterate_query(sql, name = 'SQL', binds = [], modifier = nil, query_timeout = nil, &block)
    # Variante für Rails 5
    type_casted_binds = binds.map { |attr| TypeMapper.new.type_cast(attr.value_for_database) }

    log(sql, name, binds) do
      cursor = nil
      cursor = prepare(sql)
      cursor.bind_params(type_casted_binds) if !binds.empty?

      cursor.get_raw_statement.setQueryTimeout(query_timeout.to_i) if query_timeout          # Erweiterunge gegenüber exec_query

      cursor.exec

      columns = cursor.get_col_names.map do |col_name|
        # @connection.oracle_downcase(col_name)                               # Rails 5-Variante
        oracle_downcase(col_name).freeze
      end
      fetch_options = {:get_lob_value => (name != 'Writable Large Object')}
      while row = cursor.fetch(fetch_options)
        result_hash = {}
        columns.each_index do |index|
          result_hash[columns[index]] = row[index]
          row[index] = row[index].strip if row[index].class == String   # Remove possible 0x00 at end of string, this leads to error in Internet Explorer
        end
        result_hash.extend SelectHashHelper
        modifier.call(result_hash)  unless modifier.nil?
        yield result_hash
      end

      cursor.close
      nil
    end
  end #iterate_query

  # Method comparable to ActiveRecord::ConnectionAdapters::OracleEnhancedDatabaseStatements.exec_update
  def exec_update(sql, name, binds)
    type_casted_binds = binds.map { |attr| TypeMapper.new.type_cast(attr.value_for_database) }

    log(sql, name, binds) do
      cursor = prepare(sql)
      cursor.bind_params(type_casted_binds) if !binds.empty?
      res = cursor.exec_update
      cursor.close
      res
    end
  end



end #class_eval


# Holds DB-Connection(s) to several Oracle-targets thread-safe apart from ActiveRecord

# Config for DB connection for current threads request is stored in Thread.current[:]

MAX_CONNECTION_POOL_SIZE = 20                                                   # Number of pooled connections, may be more than max. threads

class PanoramaConnection

  # Array of connection hashes, elements consists of:
  #   :jdbc_connection
  #   :used_in_thread
  #   :last_used_time
  @@connection_pool = []

  @@connection_pool_mutex = Mutex.new                                           # Ensure synchronized operations on @@connection_pool

  public
  # Store connection redentials for this request in thread, marks begin of request
  def self.set_connection_info_for_request(config)
    reset_thread_local_attributes
    Thread.current[:panorama_connection_connect_info] = config
  end

  # Ensure initialized values if thread is reused
  def self.reset_thread_local_attributes
    Thread.current[:panorama_connection_app_info_set] = nil
    Thread.current[:panorama_connection_connect_info] = nil
  end

  # Release connection at the end of request to mark free in pool or destroy
  def self.release_connection
    if Thread.current[:panorama_connection_jdbc_connection]
      @@connection_pool_mutex.synchronize do
        @@connection_pool.each do |conn|
          if conn[:jdbc_connection] == Thread.current[:panorama_connection_jdbc_connection]
            conn[:used_in_thread] = false
          end
        end
      end
      Thread.current[:panorama_connection_jdbc_connection] = nil
    end
  end

  def self.destroy_connection
    @@connection_pool_mutex.synchronize do
      destroy_connection_in_mutexed_pool(Thread.current[:panorama_connection_jdbc_connection])
    end
    Thread.current[:panorama_connection_jdbc_connection] = nil
  end

  private
  def self.destroy_connection_in_mutexed_pool(destroy_conn)
    @@connection_pool.each do |conn|
      if conn[:jdbc_connection] == destroy_conn
        config = conn[:jdbc_connection].instance_variable_get(:@config)
        Rails.logger.info "Database connection destroyed: URL='#{config[:url]}' User='#{config[:username]}' Last used=#{conn[:last_used_time]} Pool size=#{@@connection_pool.count}"
        begin
          conn[:jdbc_connection].logoff
        rescue Exception => e
          Rails.logger.info "destroy_connection_in_mutexed_pool: Exception #{e.message} during logoff. URL='#{config[:url]}' User='#{config[:username]}' Last used=#{conn[:last_used_time]}"
        end
        @@connection_pool.delete(conn)
      end
    end
  end

  def self.jdbc_thin_url
    unless Thread.current[:panorama_connection_connect_info]
      raise 'No current DB connect info set! Please reconnect to DB!'
    end
    "jdbc:oracle:thin:@#{Thread.current[:panorama_connection_connect_info][:tns]}"
  end

  def self.get_jdbc_driver_version
    Thread.current[:panorama_connection_jdbc_connection].raw_connection.getMetaData().getDriverVersion()
  rescue Exception => e
    e.message                                                                   # return Exception message instead of raising exeption
  end


  def self.sql_prepare_binds(sql)
    binds = []
    if sql.class == Array
      stmt =sql[0].clone      # Kopieren, da im Stmt nachfolgend Ersetzung von ? durch :A1 .. :A<n> durchgeführt wird
      # Aufbereiten SQL: Ersetzen Bind-Aliases
      bind_index = 0
      while stmt['?']                   # Iteration über Binds
        bind_index = bind_index + 1
        bind_alias = ":A#{bind_index}"
        stmt['?'] = bind_alias          # Ersetzen ? durch Host-Variable
        unless sql[bind_index]
          raise "bind value at position #{bind_index} is NULL for '#{bind_alias}' in binds-array for sql: #{stmt}"
        end
        raise "bind value at position #{bind_index} missing for '#{bind_alias}' in binds-array for sql: #{stmt}" if sql.count <= bind_index
        binds << ActiveRecord::Relation::QueryAttribute.new(bind_alias, sql[bind_index], ActiveRecord::Type::Value.new)   # Ab Rails 5
        # binds << [ ActiveRecord::ConnectionAdapters::Column.new(bind_alias, nil, ActiveRecord::Type::Value.new), sql[bind_index]] # Neu ab Rails 4.2.0, Abstrakter Typ muss angegeben werden
      end
    else
      if sql.class == String
        stmt = sql
      else
        raise "Unsupported Parameter-Class '#{sql.class.name}' for parameter sql of sql_select_all(sql)"
      end
    end
    [stmt, binds]
  end

  public

  # Analog sql_select all, jedoch return ResultIterator mit each-Method
  # liefert Objekt zur späteren Iteration per each, erst dann wird SQL-Select ausgeführt (jedesmal erneut)
  # Parameter: sql = String mit Statement oder Array mit Statement und Bindevariablen
  #            modifier = proc für Anwendung auf die fertige Row
  def self.sql_select_iterator(sql, modifier=nil, query_name = 'sql_select_iterator')
    check_for_open_connection                                                   # ensure opened Oracle-connection
    transformed_sql = PackLicense.filter_sql_for_pack_license(sql, Thread.current[:panorama_connection_connect_info][:management_pack_license])  # Check for lincense violation and possible statement transformation
    stmt, binds = sql_prepare_binds(transformed_sql)   # Transform SQL and split SQL and binds
    SqlSelectIterator.new(translate_sql(stmt), binds, modifier, Thread.current[:panorama_connection_connect_info][:query_timeout], query_name)      # kann per Aufruf von each die einzelnen Records liefern
  end

  # Helper fuer Ausführung SQL-Select-Query,
  # Parameter: sql = String mit Statement oder Array mit Statement und Bindevariablen
  #            modifier = proc für Anwendung auf die fertige Row
  # return Array of Hash mit Columns des Records
  def self.sql_select_all(sql, modifier=nil, query_name = 'sql_select_all')   # Parameter String mit SQL oder Array mit SQL und Bindevariablen
    result = []
    PanoramaConnection::sql_select_iterator(sql, modifier, query_name).each do |r|
      result << r
    end
    result
  end

  # Select genau erste Zeile
  def self.sql_select_first_row(sql, query_name = 'sql_select_first_row')
    result = sql_select_all(sql, nil, query_name)
    return nil if result.empty?
    result[0]     #.extend SelectHashHelper      # Erweitern Hash um Methodenzugriff auf Elemente
  end

  # Select genau einen Wert der ersten Zeile des Result
  def self.sql_select_one(sql, query_name = 'sql_select_one')
    result = sql_select_first_row(sql, query_name)
    return nil unless result
    result.first[1]           # Value des Key/Value-Tupels des ersten Elememtes im Hash
  end

  def self.sql_execute(sql, query_name = 'sql_execute')
    raise 'binds are not yet supported for sql_execute' if sql.class != String
    get_connection.exec_update(sql, query_name, [])
  end


  def self.get_connection
    check_for_open_connection
    Thread.current[:panorama_connection_jdbc_connection]
  end

  private
  # ensure that Oracle-Connection exists and DBMS__Application_Info is executed
  def self.check_for_open_connection
    if Thread.current[:panorama_connection_jdbc_connection].nil?                # No JDBC-Connection allocated for thread
      Thread.current[:panorama_connection_jdbc_connection] = retrieve_from_pool_or_create_new_connection
    end

    if Thread.current[:panorama_connection_app_info_set].nil?                   # dbms_application_info not yet set in thread
      set_application_info
      Thread.current[:panorama_connection_app_info_set] = true
    end
  end

  # get existing free connection from pool or create new one
  def self.retrieve_from_pool_or_create_new_connection
    retval = nil
    @@connection_pool_mutex.synchronize do
      # Check if there is a free connection in pool
      @@connection_pool.each do |conn|                                          # Iterate over connections in pool
        connection_config = conn[:jdbc_connection].instance_variable_get(:@config)  # Active JDBC connection config
        if retval.nil? &&                                                       # Searched connection, not already in use
            !conn[:used_in_thread] &&
            connection_config[:url] == jdbc_thin_url &&
            connection_config[:username] == Thread.current[:panorama_connection_connect_info][:user]
          Rails.logger.info "Using existing database connection from pool: URL='#{jdbc_thin_url}' User='#{Thread.current[:panorama_connection_connect_info][:user]}' Last used=#{conn[:last_used_time]} Pool size=#{@@connection_pool.count}"
          conn[:used_in_thread] = true                                          # Mark as used in pool and leave loop
          conn[:last_used_time] = Time.now                                      # Reset ast used time
          retval = conn[:jdbc_connection]
        end
      end
    end
    # Create new connection if not found in pool
    if retval.nil?
      raise "Native ruby (RUBY_ENGINE=#{RUBY_ENGINE}) is no longer supported! Please use JRuby runtime environment! Call contact for support request if needed." if !defined?(RUBY_ENGINE) || RUBY_ENGINE != "jruby"

      # Shrink connection pool / reuse connection from pool if size exceeds limit
      if @@connection_pool.count >= MAX_CONNECTION_POOL_SIZE
        # find oldest idle connection and free it
        @@connection_pool_mutex.synchronize do
          idle_conns =  @@connection_pool.select {|e| !e[:used_in_thread] }.sort { |a, b| a[:last_used_time] <=> b[:last_used_time] }
          destroy_connection_in_mutexed_pool(idle_conns[0]) if !idle_conns.empty?               # Free oldest conenction
        end
        raise "Maximum number of active concurrent database sessions for Panorama exceeded (#{MAX_CONNECTION_POOL_SIZE})!\nPlease try again later." if @@connection_pool.count >= MAX_CONNECTION_POOL_SIZE
      end

      begin
        local_password = Encryption.decrypt_value(Thread.current[:panorama_connection_connect_info][:password], Thread.current[:panorama_connection_connect_info][:client_salt])
      rescue Exception => e
        Rails.logger.warn "Error in PanoramaConnection.retrieve_from_pool_or_create_new_connection decrypting pasword: #{e.message}"
        raise "One part of encryption key for stored password has changed at server side! Please connect giving username and password."
      end

      jdbc_connection = ActiveRecord::ConnectionAdapters::OracleEnhancedJDBCConnection.new(
          :adapter    => "oracle_enhanced",
          :driver     => "oracle.jdbc.driver.OracleDriver",
          :url        => jdbc_thin_url,
          :username   => Thread.current[:panorama_connection_connect_info][:user],
          :password   => local_password,
          :privilege  => Thread.current[:panorama_connection_connect_info][:privilege],
          :cursor_sharing => :exact             # oracle_enhanced_adapter setzt cursor_sharing per Default auf force
      )
      Rails.logger.info "New database connection created: URL='#{jdbc_thin_url}' User='#{Thread.current[:panorama_connection_connect_info][:user]}' Pool size=#{@@connection_pool.count+1}"

      @@connection_pool_mutex.synchronize do
        @@connection_pool << {
            :jdbc_connection => jdbc_connection,
            :used_in_thread => true,
            :last_used_time => Time.now
        }
        retval = jdbc_connection
      end
    end
    retval
  end

  def self.set_application_info
    # This method raises connection exception at first database access
    Thread.current[:panorama_connection_jdbc_connection].exec_update("call dbms_application_info.set_Module('Panorama', :action)", nil,
                                  [ActiveRecord::Relation::QueryAttribute.new(':action', "#{Thread.current[:panorama_connection_connect_info][:current_controller_name]}/#{Thread.current[:panorama_connection_connect_info][:current_action_name]}", ActiveRecord::Type::Value.new)]
    )

  end

  # Translate text in SQL-statement
  def self.translate_sql(stmt)
    stmt.gsub!(/\n[ \n]*\n/, "\n")                                                  # Remove empty lines in SQL-text
    stmt
  end


  class SqlSelectIterator

    # Remember this parameters for execution at method each
    # stmt - SQL-String
    # binds - Parameter-Array
    def initialize(stmt, binds, modifier, query_timeout, query_name = 'SqlSelectIterator')
      @stmt           = stmt
      @binds          = binds
      @modifier       = modifier              # proc for modifikation of record
      @query_timeout  = query_timeout
      @query_name     = query_name
    end

    def each(&block)
      # Execute SQL and call block for every record of result
      Thread.current[:panorama_connection_jdbc_connection].iterate_query(@stmt, @query_name, @binds, @modifier, @query_timeout, &block)
    rescue Exception => e
      bind_text = ''
      @binds.each do |b|
        bind_text << "#{b.name} = #{b.value}\n"
      end

      # Ensure stacktrace of first exception is show
      new_ex = Exception.new("Error while executing SQL:\n\n#{e.message}\n\n#{bind_text.length > 0 ? "Bind-Values:\n#{bind_text}" : ''}")
      new_ex.set_backtrace(e.backtrace)
      raise new_ex
    end

  end

end