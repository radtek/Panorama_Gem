# encoding: utf-8

require 'json'
class DragnetController < ApplicationController
  include DragnetHelper

  # Show dialog
  def show_selection
    params[:update_area] = :content_for_layout
    render_partial :show_selection
  end

  # Auswahl-Liste für jstree als json -Array mit folgender Struktur
  # Expected format of the node in json buffer (there are no required fields)
  # {
  #   id          : "string" // will be autogenerated if omitted
  #   text        : "string" // node text
  #   icon        : "string" // string for custom
  #   state       : {
  #     opened    : boolean  // is the node open
  #     disabled  : boolean  // is the node disabled
  #     selected  : boolean  // is the node selected
  #   },
  #   children    : []  // array of strings or objects
  #   li_attr     : {}  // attributes for the generated LI node
  #   a_attr      : {}  // attributes for the generated A node
  # }
  def get_selection_list
    filter = params[:filter]
    filter = nil if filter == ''
    include_description = params[:include_description] == 'true'

    # liefert einen Eintrag mit Untermenu
    def render_entry_json(global_id_prefix, inner_id, entry, filter, include_description)
      filtered_entry_count = 0                                                 # Anzahl dem Filter entsprechende Einträge, egal ob Knoten oder Abfrage
      result =
          "{
  \"id\": \"#{"#{global_id_prefix}_#{inner_id}"}\",
  \"text\": \"#{inner_id+1}. #{entry[:name]}\",
  \"state\": { \"opened\": false }
"
      if entry[:entries]                                                        # Menu-Knoten
        result << ", \"children\": [ "                                          # Space nach [ um leere Position entfernen zu können, wenn kein Nachfolger mit Komma getrennt
        entry_id = 0
        entry[:entries].each do |e|
          subresult = render_entry_json("#{global_id_prefix}_#{inner_id}", entry_id, e, filter, include_description)
          if subresult
            result << subresult
            filtered_entry_count = filtered_entry_count + 1
          end
          entry_id = entry_id + 1
        end
        result[result.length-1] = ' '                                           # letztes Komma entfernen
        result << "]"
      else
        result << ", \"icon\":\"assets/application-monitor.png\""
      end
      result << "},"
      return nil if filter && entry[:entries] && filtered_entry_count == 0      # Anzeige unterdrücken wenn Knoten keine Treffer für Filter hat
      return nil if filter && !entry[:entries] && !entry[:name].upcase[filter.upcase] &&  !(entry[:desc].upcase[filter.upcase] && include_description)
      result
    end # render_entry_json

    response = '[ '                                                             # JSON-Buffer
    entry_id = 0
    dragnet_sql_list.each do |s|
      subresult = render_entry_json('', entry_id, s, filter, include_description)
      response << subresult if subresult
      entry_id = entry_id + 1
    end
    response[response.length-1] = ' '                                           # letztes Komma entfernen
    response << ']'

    render :json => response.html_safe, :status => 200
  end # get_selection_list


  # Show new selection diealog
  def refresh_selected_data
    entry = extract_entry_by_entry_id(params[:entry_id])

    parameter = ""
    if entry[:parameter]        # Parameter erwähnt (erwartet als Array)
      entry[:parameter].each do |p|
        parameter << "<div title='#{my_html_escape(p[:title])}'>#{my_html_escape(p[:name])} <input name='#{p[:name]}' size='#{p[:size]}' value='#{p[:default]}' type='text'></div><br/>"
      end
    end
    respond_to do |format|
      format.js {render :js => "$('#show_selection_header_area').html('<b>#{j my_html_escape(entry[:name]) }</b>');
                                $('#show_selection_hint_area').html('#{j my_html_escape(entry[:desc]) }');
                                $('#show_selection_param_area').html('#{j parameter }');
                                $('#dragnet_show_selection_do_selection').prop('disabled', #{entry[:sql] ? 'false' : 'true'});
                                $('#dragnet_show_selection_show_sql').prop('disabled', #{entry[:sql] ? 'false' : 'true'});
                                $('#dragnet_drop_personal_selection_button').#{entry[:personal] ? 'show' : 'hide'}();
                                $('#dragnet_hidden_entry_id').val('#{params[:entry_id]}');
                               "
      }
    end
  end


  # Ausführen Report
  def exec_dragnet_sql
    dragnet_sql = extract_entry_by_entry_id(params[:dragnet_hidden_entry_id])

    if params[:commit_show]    # Verzweigen auf weitere Funktion bei Anwahl zweiter Button
      show_used_sql(dragnet_sql)
      return
    end

    # Headerzeile des Report erstellen, Parameter ermitteln
    @caption = "#{dragnet_sql[:name]}"
    command_array = [dragnet_sql[:sql]]
    if dragnet_sql[:parameter]
      @caption << ": "
      dragnet_sql[:parameter].each do |p|   # Binden evtl. Parameter
        command_array << params[p[:name]]           # Parameter aus Form mit Name erwartet
        @caption << " '#{p[:name]}' = #{params[p[:name]]}"  # Ausgabe im Header
      end
    end

    # Ausführen des SQL
    @res = sql_select_all command_array

    # Optionales Filtern des Results
    if dragnet_sql[:filter_proc]
      raise "filter_proc muss Klasse proc besitzen für #{dragnet_sql[:name]}" if dragnet_sql[:filter_proc].class.name != 'Proc'
      res = []
      @res.each do |r|
        res << r if dragnet_sql[:filter_proc].call(r)
      end
      @res = res
    end

    render_partial :list_dragnet_sql_result
  end

  def show_used_sql(dragnet_sql)
    show_value = dragnet_sql[:sql]                                              # Default
    if dragnet_sql[:personal]
      show_dn = dragnet_sql.clone
      show_dn.delete(:personal)                                                 # should not be shown
      show_value = JSON.pretty_generate(show_dn)
    end

    respond_to do |format|

      format.html {render :html => render_yellow_pre(show_value, 450) }
    end
  end


  def show_personal_selection_form
    render_partial
  end

  private
  # Kompletten Menu-Baum durchsuchen nach Name und raise bei Dopplung
  def look_for_double_names(list, double_names)
    list.each do |l|
      look_for_double_names(l[:entries], double_names) if l[:entries]
      double_names[l[:name]] = 0 unless double_names[l[:name]]
      double_names[l[:name]] = double_names[l[:name]] + 1
    end
  end

  public
  def add_personal_selection
    dragnet_personal_selection_list = read_from_client_info_store(:dragnet_personal_selection_list)
    dragnet_personal_selection_list = [] if dragnet_personal_selection_list.nil?

    begin
      new_selection = eval(params[:selection])
    rescue Exception => e
      raise "Error \"#{e.message}\" during parse of your selection"
    end

    new_selection = [new_selection] if new_selection.class == Hash              # ab jetzt immer Array
    dragnet_personal_selection_list.concat(new_selection)                       # Add to possibly existing

    double_names = {}
    look_for_double_names(dragnet_personal_selection_list, double_names)
    double_names.each do |key, value|
      raise "Error: Name \"#{key}\" is duplicated" if value > 1
    end

    write_to_client_info_store(:dragnet_personal_selection_list, dragnet_personal_selection_list)

    @@dragnet_internal_list = nil                                               # require new build of list with next request
    show_selection                                                              # Show edited selection list again
  end

  private
  # Kompletten Menu-Baum durchsuchen nach Name und drop der Treffer
  def drop_external_selection(list, name)
    list.each do |l|
      unless l.nil?                                                             # already deleted entry of list
        drop_external_selection(l[:entries], name) if l[:entries]
        list.delete(l) if l[:name] == name
      end
    end
  end


  public
  # Drop selection from personal list
  def drop_personal_selection
    drop_selection = extract_entry_by_entry_id(params[:dragnet_hidden_entry_id])


    dragnet_personal_selection_list = read_from_client_info_store(:dragnet_personal_selection_list)

    drop_external_selection(dragnet_personal_selection_list, drop_selection[:name])

    write_to_client_info_store(:dragnet_personal_selection_list, dragnet_personal_selection_list)

    @@dragnet_internal_list = nil                                               # require new build of list with next request
    show_selection                                                              # Show edited selection list again
  end



end
