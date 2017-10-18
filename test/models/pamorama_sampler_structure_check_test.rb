require 'test_helper'

class PanoramaSamplerStructureCheckTest < ActiveSupport::TestCase

  setup do
    @sampler_config = prepare_panorama_sampler_thread_db_config
  end


  test "has_column?" do
    assert_equal(true, PanoramaSamplerStructureCheck.has_column?('Panorama_Snapshot', 'Snap_ID'))
  end

  test "replacement_table" do
    assert_equal('Panorama_Snapshot', PanoramaSamplerStructureCheck.replacement_table('DBA_Hist_Snapshot'))
    assert_nil(PanoramaSamplerStructureCheck.replacement_table('Dummy'))
  end

  test 'tables' do
    assert_equal(PanoramaSamplerStructureCheck.tables.class, Array)
    assert(PanoramaSamplerStructureCheck.tables.length > 0)
  end

  test 'panorama_sampler_schemas' do
    assert_equal(PanoramaSamplerStructureCheck.panorama_sampler_schemas.class, Array)
  end

  test 'transform_sql_for_sampler' do
    assert_equal(PanoramaSamplerStructureCheck.transform_sql_for_sampler("SELECT * FROM DBA_Hist_SQLStat").upcase,          "SELECT * FROM PANORAMA_TEST.PANORAMA_SQLSTAT")
    assert_equal(PanoramaSamplerStructureCheck.transform_sql_for_sampler("SELECT * FROM gv$Active_Session_History").upcase, "SELECT * FROM PANORAMA_TEST.PANORAMA_V$ACTIVE_SESS_HISTORY")
    assert_equal(PanoramaSamplerStructureCheck.transform_sql_for_sampler("SELECT * FROM DBA_Hist_Hugo").upcase,             "SELECT * FROM DBA_HIST_HUGO")
  end

  test 'adjust_table_name' do
    config = PanoramaConnection.get_config

    config[:management_pack_license] = :none
    PanoramaConnection.set_connection_info_for_request(config)
    assert_equal(PanoramaSamplerStructureCheck.adjust_table_name('DBA_Hist_SQLStat'), 'DBA_Hist_SQLStat')

    config[:management_pack_license] = :panorama_sampler
    PanoramaConnection.set_connection_info_for_request(config)
    assert_equal(PanoramaSamplerStructureCheck.adjust_table_name('DBA_Hist_SQLStat'), 'panorama_test.Panorama_SQLStat')

  end

  test 'do_check' do
    2.downto(1) do
      PanoramaSamplerStructureCheck.do_check(@sampler_config, :ASH)
      PanoramaSamplerStructureCheck.do_check(@sampler_config, :AWR)
      PanoramaSamplerStructureCheck.do_check(@sampler_config, :OBJECT_SIZE)
    end
  end
end