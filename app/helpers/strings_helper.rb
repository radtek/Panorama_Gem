# encoding: utf-8
module StringsHelper
  @@strings_list = {
      sql_monitor_link_title: "Generate SQL-Monitor report by calling DBMS_SQLTUNE.report_sql_monitor on new page.
- requires active internet connection at client
- requires Adobe Flash installed at client browser
- requires licensing of Oracle Tuning Pack
- Available only if data exists in gv$SQL_Monitor

Click link at column 'SQL exec ID' to generate SQL-Monitor report if there are multiple results",
      sql_monitor_list_title: I18n.t(:strings_sql_monitor_list_hint, default: "List recorded SQL-Monitor reports from gv$SQL_Monitor and DBA_HIST_Reports\nClick Report-ID to show choosen SQL-Monitor report in separate browser tab."),

  }
  def strings(key)
    raise "StringsHelper.strings: Key '#{key}' not found in predfined strings" unless @@strings_list[key]
    @@strings_list[key]
  end
end