require "test_helper"

class SpecAdditionsTest < ApplicationSystemTestCase

  test "Dragnet investigation" do
    # Call menu entry
    login_and_menu_call('Spec. additions', 'menu_dragnet_show_selection')
    assert_ajax_success
    sleep 2                                                                     # Wait for content displayed

    assert_text 'Dragnet investigation for performance bottlenecks and usage of anti-pattern'
    assert_text 'Select dragnet-SQL for execution'
    assert_text '1. Potential in DB-structures'

    # click first node
    page.first(:xpath, "//i[contains(@class, 'jstree-icon') and contains(@class, 'jstree-ocl') and contains(@role, 'presentation')]").click
    assert_ajax_success
    assert_text '1. Ensure optimal storage parameter for indexes'

    # click point 1.6
    page.first(:xpath, "//a[contains(@id, '_0_5_anchor')]").click
    assert_ajax_success
    assert_text 'Protection of colums with foreign key references by index can be necessary for'

    # Click "Show SQL"                                       ^
    page.first(:xpath, "//input[contains(@type, 'submit') and contains(@name, 'commit_show')]").click
    assert_ajax_success
    assert_text 'FROM   DBA_Constraints Ref'

    # Click "Do selection"
    page.first(:xpath, "//input[contains(@type, 'submit') and contains(@name, 'commit_exec')]").click
    assert_ajax_success

  end

end