# encoding: utf-8
require 'test_helper'
require 'active_session_history_helper'

class ActiveSessionHistoryControllerTest < ActionController::TestCase
  include ActiveSessionHistoryHelper

  setup do
    #@routes = Engine.routes         # Suppress routing error if only routes for dummy application are active
    set_session_test_db_context{
      min_alter_org = Time.new
      max_alter_org = min_alter_org-10000
      @time_selection_end = min_alter_org.strftime("%d.%m.%Y %H:%M")
      @time_selection_start = (max_alter_org).strftime("%d.%m.%Y %H:%M")

      snaps = sql_select_first_row ["SELECT /* Panorama-Tool Ramm */ MAX(Snap_ID) Min_Snap_ID, MAX(Snap_ID) Max_Snap_ID
                                    FROM   DBA_Hist_Snapshot
                                    WHERE  DBID = ?
                                    AND    Begin_Interval_Time BETWEEN ? AND ?
                                   ", get_dbid, max_alter_org, min_alter_org]
      @min_snap_id = snaps.min_snap_id
      @max_snap_id = snaps.max_snap_id
      @groupfilter = {
                :DBID            => get_dbid,
                :time_selection_start => @time_selection_start,
                :time_selection_end   => @time_selection_end,
                :Min_Snap_ID     => @min_snap_id,
                :Max_Snap_ID     => @max_snap_id
        }
    }
  end

  # Workaround, da t in Test-Klassen nicht bekannt ist
  def t(hook, translate_hash)
    translate_hash[:default]
  end

  # Ermittlung der zum Typ passenden Werte für Bindevariablen
  def bind_value_from_key_rule(key)
    case key
      when "User"         then 'Hugo'
      when "SQL-ID"       then '123456789'
      when "Session/Sn."  then '1,2'
      when "Operation"    then 'FULL SCAN'
      when "Entry-PL/SQL" then 'Hugo<>%&'
      when "PL/SQL"       then 'Hugo<>%&'
      when "Module"       then 'Module1<>%&'
      when 'Modus'        then 'SQL exec'
      when "Action"       then 'Action1<>%&'
      when "Event"        then 'db file sequential read'
      when "Wait-Class"   then 'IO'
      when "DB-Object"    then 'DUAL'
      when "DB-Sub-Object"  then 'DUAL'
      when "Service"      then 'DEFAULT'
      when 'Tablespace'   then 'SYSTEM'
      when "Program"      then 'sqlplus<>%&'
      when "Machine"      then 'ramm.osp-dd.de<>%&'
      when 'PQ'           then '1:2:3'
      when 'Session-Type' then 'F'
      else 2
    end
  end

  # Alle Menu-Einträge testen für die der Controller eine Action definiert hat
  test "test_controllers_menu_entries_with_actions" do
    call_controllers_menu_entries_with_actions
  end

  test "list_session_statistics_historic" do
    # Iteration über Gruppierungskriterien
    session_statistics_key_rules.each do |groupby, value|
      post :list_session_statistic_historic, :params => {:format=>:js, :time_selection_start=>@time_selection_start, :time_selection_end=>@time_selection_end, :groupby=>groupby }
      assert_response :success

      post :list_session_statistic_historic, :params => {:format=>:js, :time_selection_start=>@time_selection_start, :time_selection_end=>@time_selection_end, :groupby=>groupby, :filter=>'sys'}
      assert_response :success
    end
  end

  test "list_session_statistic_historic_grouping" do
    session_statistics_key_rules.each do |outer_groupby, value_outer|
      # Iteration über Gruppierungskriterien
      session_statistics_key_rules.each do |groupby, value_inner|
        # Test mit realem Wert
        add_filter = {outer_groupby => bind_value_from_key_rule(outer_groupby)}
        post :list_session_statistic_historic_grouping, :params => {:format=>:js, :groupby=>groupby, :groupfilter => @groupfilter.merge(add_filter) }
        assert_response :success

        post :list_session_statistic_historic_grouping, :params => {:format=>:js, :groupby=>groupby, :groupfilter => @groupfilter.merge(add_filter).merge(:Additional_Filter=>'sys') }
        assert_response :success

        # Test mit NULL als Filterkriterium
        add_filter = {outer_groupby => nil}
        post :list_session_statistic_historic_grouping, :params => {:format=>:js, :groupby=>groupby, :groupfilter => @groupfilter.merge(add_filter) }
        assert_response :success

        post :list_session_statistic_historic_grouping, :params => {:format=>:js, :groupby=>groupby, :groupfilter => @groupfilter.merge(add_filter).merge(:Additional_Filter=>'sys') }
        assert_response :success
      end
    end
  end

  test "refresh_time_selection" do
    session_statistics_key_rules.each do |groupby, value|
      post :refresh_time_selection, :params => {:format=>:js, :groupfilter=>@groupfilter, :groupby=>groupby, :repeat_action => :list_session_statistic_historic_grouping }
      assert_response :success   # redirect_to schwierig im Test?
    end
  end

  test "list_session_statistic_historic_single_record" do
    session_statistics_key_rules.each do |groupby, value|
      add_filter = {groupby => bind_value_from_key_rule(groupby)}
      post :list_session_statistic_historic_single_record, :params => {:format=>:js, :groupby=>groupby,
           :groupfilter=>@groupfilter.merge(add_filter) }
      assert_response :success
    end
  end

  test "list_session_statistics_historic_timeline" do
    session_statistics_key_rules.each do |groupby, value|
      add_filter = {groupby => bind_value_from_key_rule(groupby)}
      post :list_session_statistic_historic_timeline, :params => {:format=>:js, :groupby=>groupby,
           :groupfilter=>@groupfilter.merge(add_filter),
           :top_values => ["1", "2", "3"], :group_seconds=>60 }
      assert_response :success
    end
  end

  test "list_temp_usage_historic" do
    if get_db_version >= "11.2"
      session_statistics_key_rules.each do |outer_filter, value|
        # Iteration über Gruppierungskriterien
        temp_historic_grouping_options.each do |time_groupby, inner_value|
          add_filter = {outer_filter => bind_value_from_key_rule(outer_filter)}
          post :list_temp_usage_historic, :params => {:format=>:js, :time_groupby=>time_groupby, :groupfilter => @groupfilter.merge(add_filter) }
          assert_response :success
        end
      end
    end
  end


  test "show_prepared_active_session_history" do
    post :show_prepared_active_session_history, :params => {:format=>:js, :instance=>1, :sql_id=>@sga_sql_id }
    assert_response :success
    post :show_prepared_active_session_history, :params => {:format=>:js, :instance=>1, :sid=>@sid }
    assert_response :success
  end

  test "list_prepared_active_session_history" do
    post :list_prepared_active_session_history, :params => {:format=>:js, :groupby=>"SQL-ID",
         :groupfilter => {
                         :DBID     => get_dbid,
                         :Instance => 1,
                         "SQL-ID"  => @sga_sql_id
         },
         :time_selection_start => @time_selection_start,
         :time_selection_end   => @time_selection_end }
    assert_response :success
  end

  test "blocking_locks_historic" do
    post :list_blocking_locks_historic, :params => {:format=>:js, :time_selection_start=>@time_selection_start, :time_selection_end=>@time_selection_end }
    assert_response :success
  end


end
