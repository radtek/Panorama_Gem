# encoding: utf-8

module ExplainPlanHelper

  def calculate_execution_order_in_plan(plan_array)
    pos_array = []

    # Vergabe der exec-Order im Explain
    # iteratives neu durchsuchen der Liste nach folgenden erfuellten Kriterien
    # - ID tritt nicht als Parent auf
    # - alle Children als Parent sind bereits mit ExecOrder versehen
    # gefundene Records werden mit aufteigender Folge versehen und im folgenden nicht mehr betrachtet

    # Array mit den Positionen der Objekte in plans anlegen
    0.upto(plan_array.length-1) {|i|  pos_array << i }

    plan_array.each do |p|
      p[:is_parent] = false                                                     # Vorbelegung
    end

    curr_execorder = 1                                             # Startwert
    while pos_array.length > 0                                     # Bis alle Records im PosArray mit Folge versehen sind
      pos_array.each {|i|                                          # Iteration ueber Verbliebene Records
        is_parent = false                                          # Default-Annahme, wenn kein Child gefunden
        pos_array.each {|x|                                        # Suchen, ob noch ein Child zum Parent existiert in verbliebener Menge
          if plan_array[i].id == plan_array[x].parent_id           # Doch noch ein Child zum Parent gefunden
            is_parent = true
            plan_array[i][:is_parent] = true                       # Merken Status als Knoten
            break                                                  # Braucht nicht weiter gesucht werden
          end
        }
        unless is_parent
          plan_array[i].execorder = curr_execorder                      # Vergabe Folge
          curr_execorder = curr_execorder + 1
          pos_array.delete(i)                                      # entwerten der verarbeiten Zeile fuer Folgebetrachtung
          pos_array = pos_array.compact                            # Entfernen der gelöschten Einträge (eventuell unnötig)
          break                                                    # Neue Suche vom Beginn an
        end
      }
    end
  end


  # Build tree with tabbed inserts for column operation
  def list_tree_column_operation(rec, indent_vector, plan_array)
    tab = ""
    toggle_id = "#{get_unique_area_id}_#{rec.id}"

    if rec.depth > indent_vector.count                                        # Einrückung gegenüber Vorgänger
      last_exists_id = 0                                                       # ID des letzten Records, für den die selbe parent_id existiert
      plan_array.each do |p|
        if p.id > rec.id &&  p.parent_id == rec.parent_id                      # nur Nachfolger des aktuellen testen, letzte Existenz des parent_id suchen
          last_exists_id = p.id
        end
      end
      indent_vector << {:parent_id => rec.parent_id, :last_exists_id => last_exists_id}
    end

    while rec.depth < indent_vector.count                                   # Einrückung gegenüber Vorgänger
      indent_vector.delete_at(indent_vector.count-1);
    end

    #rec.depth.downto(1) {
    #  tab << "<span class=\"toggle\"></span>&nbsp;"
    #}

    indent_vector.each_index do |i|
      if i < indent_vector.count-1                                          # den letzten Eintrag unterdrücken, wird relevant beim nächsten, wenn der einen weiter rechts eingerückt ist
        v = indent_vector[i]
        tab << "<span class=\"toggle #{'vertical-line' if rec.id < v[:last_exists_id]}\" title=\"parent_id=#{v[:parent_id]} last_exists_id=#{v[:last_exists_id]}\">#{'' if rec.id < v[:last_exists_id]}</span>&nbsp;"
      end
    end


    if rec[:is_parent]                                                       # Über hash ansprechen, da in bestimmten Konstellationen der Wert nicht im hash enthalten ist => false
      if rec.id > 0                                                          # 1. und 2. Zeile haben gleiche Einrückung durch weglassen des letzten Eintrages von indent_vector, hiermit bleibt 1. Zeile trotzde, weiter links
        tab << "<a class=\"toggle collapse\" id=\"#{toggle_id}\" onclick=\"explain_plan_toggle_expand('#{toggle_id}', #{rec.id}, #{rec.depth}, '#{@grid_id}');\"></a>"
      end
    else
      if plan_array.count > rec.id+1 && plan_array[rec.id+1].parent_id == rec.parent_id # Es gibt noch einen unmittelbaren Nachfolger mit selber Parent-ID
        tab << "<span class=\"toggle vertical-corner-line\"></span>"         # durchgehende Linie mit abzweig
      else
        tab << "<span class=\"toggle corner-line\"></span>"                  # Nur Linie mit Abzweig
      end
    end
    tab << "&nbsp;"
    "<span style=\"color: lightgray;\">#{tab}</span>#{rec.operation} #{rec.options}".html_safe

  end

  # build data title for columns cost and cardinality
  def cost_card_data_title(rec)
    "%t\n#{"
Optimizer mode = #{rec.optimizer}"          if rec.optimizer}#{"
CPU cost = #{fn rec.cpu_cost}"              if rec.cpu_cost}#{"
IO cost = #{fn rec.io_cost}"                if rec.io_cost}#{"
estimated bytes = #{fn rec.bytes}"          if rec.bytes}#{"
estimated time (secs.) = #{fn rec.time}"    if rec.time}#{"
partition start = #{rec.partition_start}"   if rec.partition_start}#{"
partition stop = #{rec.partition_stop}"     if rec.partition_stop}#{"
partition ID = #{rec.partition_id}"         if rec.partition_id}
    "
  end

  def parallel_short(rec)
    case rec.other_tag
    when 'PARALLEL_COMBINED_WITH_PARENT' then 'PCWP'
    when 'PARALLEL_COMBINED_WITH_CHILD'  then 'PCWC'
    when 'PARALLEL_FROM_SERIAL'          then 'S > P'
    when 'PARALLEL_TO_PARALLEL'          then 'P > P'
    when 'PARALLEL_TO_SERIAL'            then 'P > S'
    when 'SINGLE_COMBINED_WITH_CHILD'    then 'SCWC'
    when 'SINGLE_COMBINED_WITH_PARENT'   then 'SCWP'
    else
      rec.other_tag
    end
  end

end


