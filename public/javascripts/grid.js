Grid = {
  grids: {},
  grid_c: 0,
};

if (Prototype.Browser.WebKit) {
  Grid.default_input = "<input type='text' value=''/>"
  Grid.paste_mode = 'redirect'
} else {
  Grid.default_input = '<textarea></textarea>'
  Grid.paste_mode = 'inline'
}

Grid.log = function(what, msg) {
  var log = $('log')
  if (typeof(msg) != 'string') msg = Object.toJSON(msg)
  log.innerHTML = log.innerHTML + '<br/><b>' + what + '</b> ' + msg
}

Grid.changed = function(cell, val, prev, skip_html) {
  if (!skip_html) {
    if (val.value == val.show) {
      cell.innerHTML = val.value
    } else {
      cell.innerHTML = val.show
      cell.setAttribute('data-v', val.value)
    }
  }
  var row = cell.up('tr')
  var table = row.up('table')
  var grid = table.grid
  if (prev.value == val.value) return;
  if (cell.orig_value == val.value) {
    cell.removeClassName('changed')
    if (row.select('.changed').length == 0) {
      row.removeClassName('changed')
    }
  } else {
    cell.addClassName('changed')
    row.addClassName('changed')
  }
  var pos = Grid.pos(cell)

  var attr, id
  if (grid.attr_name) {
    attr = pos;
    id = Grid.pos(row) - 1;
  } else {
    attr = grid.attr[pos];
    id = row.id;
    if (!id) {
      // Prepare for create
      id = Grid.buildObj(grid, row)
    }
  }

  var change = {
    id: id,
    _old: prev,
  };
  change[attr] = val;
  var table = row.up('table');
  grid.changes.push(change);
}

// Push a row as a new object in changes.
Grid.buildObj = function(grid, row) {
  // Set a temporary id
  grid.counter++
  var id = 'new_' + grid.id + '_' + grid.counter
  row.id = id
  row.addClassName('new')
  var base = {
    id: id,
    _new: {value:true}
  }
  // Add all default attributes
  grid.defaults.each(function(pair) {
    base[pair.key] = pair.value
  })
  // Add all attributes
  var cells = row.childElements()
  for (var i = 0; i < cells.length - 1; i++) {
    var cell  = cells[i]
    var attr = grid.attr[i]
    if (attr) {
      // A readonly cell *MUST* have data-v set or it is ignored.
      if (!cell.getAttribute('data-v') && Grid.isReadOnly(cell)) continue
      var val = Grid.getValue(cell)
      if (val.value.strip() == '') {
        val = base[attr] || val
      } else {
        base[attr] = val
      }
      if (cell.innerHTML.strip() == '') {
        cell.innerHTML = val.show
      }
    }
  }
  grid.changes.push(base)
  return id
}

Grid.closeCell = function(e) {
  if (Grid.in_paste) return
  var cell = e.tagName ? e : e.element().up()
  var table = cell.up('table')
  var prev = cell.prev_value
  var val  = Grid.getValue(cell)

  if (table.grid.list_name) {
    if (val.value == 'on') {
      cell.addClassName('on')
    } else {
      cell.removeClassName('on')
    }
  } else {
    cell.removeClassName('input')
  }

  Grid.changed(cell, val, prev)

  if (table.grid.input) {
    // single attribute table, serialize in input field
    table.grid.input.value = Grid.serialize(table)
  }
}

Grid.pos = function(elem) {
  var sibl = elem.up().childElements();
  for (var i = 0; i < sibl.length; i++) {
    if (sibl[i] === elem) return i;
  }
}

Grid.paste = function(event) {
  var input = event.element();
  var start_cell  = input.up();
  var row   = start_cell.up();
  var table = row.up('table');
  var row_offset = Grid.pos(row);
  var tbody = table.childElements()[0];
  var rows = tbody.childElements();
  var cell_offset = Grid.pos(start_cell);

  var paster
  if (Grid.paste_mode == 'redirect') {
    // Redirect paste inside the paste textarea
    $(document.body).insert({
      bottom: "<textarea style='position:fixed; top:0; left:10100px;' id='grid_p_" + table.grid.id + "'></textarea>"
    });
    paster = $("grid_p_" + table.grid.id);
    Grid.in_paste = true // prevent original input blur
    paster.focus();
    Grid.in_paste = false
  }
  setTimeout(function() {
    var text
    if (Grid.paste_mode == 'redirect') {
      text = paster.value
      paster.remove()
      input.focus()
    } else {
      text = input.value
    }

    var lines = text.strip().split(/\r\n|\r|\n/);
    for (var i = 0; i < lines.length; i++) {
      lines[i] = lines[i].split(/\t/);
    }
    if (lines.length == 1 && lines[0].length == 1) {
      // simple case
      input.value = lines[0][0];
    } else {
      // copy/paste from spreadsheet
      table.grid.changes.push('start')
      var should_create = table.grid.input && true;
      for (var i = 0; i < lines.length; i++) {
        // foreach line
        // get row
        var row = rows[row_offset + i];
        if (!row) {
          if (!should_create) break;
          // create a new row
          Grid.addRow(table, rows[row_offset + i - 1]);
          rows = tbody.select('tr');
          row = rows[row_offset + i];
        }
        var tabs = lines[i];
        var cells = row.childElements(); cells.pop();
        for (var j = 0; j < tabs.length; j++) {
          // foreach tab
          var cell = cells[cell_offset + j];
          if (!cell) {
            if (!should_create) break;
            // create a new cell
            Grid.addCol(table, cells[cell_offset + j - 1]);
            cells = row.childElements(); cells.pop();
            cell = cells[cell_offset + j];
          }
          var val = {value:tabs[j], show:tabs[j]}
          if (i==0 && j==0) {
            input.value = val.value
            Grid.changed(cell, val, cell.prev_value, true)
            cell.prev_value = val
          } else if (!Grid.isReadOnly(cell)) {
            var prev = Grid.getValue(cell)
            Grid.changed(cell, val, prev)
          }
        }
      }
      table.grid.changes.push('end')
    }
    if (table.grid.input) {
      // single attribute table, serialize in input field
      table.grid.input.value = Grid.serialize(table)
    }
  }, 0)
  return true;
}

Grid.keydown = function(event) {
  var input = event.element()
  var key = event.keyCode
  var cell = input.up()
  var grid = cell.up('table').grid
  if (grid.keydown && grid.keydown(event, key)) {
    event.stop()
    return false
  }
  if ((false && key == 39) || (key == 9 && !event.shiftKey)) {
    // tab + key right
    var next = cell.nextSiblings()[0];
    if (!next || next.hasClassName('action')) {
      // wrap around on tab
      var row = cell.up('tr').nextSiblings()[0];
      if (!row) {
        row = cell.up('tbody').childElements()[1];
      }
      next = row.childElements()[0];
    }
    Grid.openCell(next);
    event.stop();
  } else if ((false && key == 37) || (key == 9 && event.shiftKey)) {
    // shift-tab + left key
    var prev = cell.previousSiblings()[0];
    if (!prev) {
      // wrap back around on shift+tab
      var row = cell.up('tr').previousSiblings()[0]
      if (!row || row.hasClassName('action')) {
        row = cell.up('tbody').childElements().last();
      }
      prev = row.childElements().last();
      if (prev.hasClassName('action'))
        prev = prev.previousSiblings()[0];
    }
    Grid.openCell(prev);
    event.stop();
  } else if ((key == 40 && event.altKey) || (key == 13 && !event.shiftKey)) {
    // down
    if (event.altKey) {
      Grid.copy(cell, 'down')
      event.stop()
      return false
    } else if (cell.childElements().first().tagName == 'SELECT' && event.shiftKey) {
      return
    }
    var pos = Grid.pos(cell);
    // go to next row
    var crow = cell.up();
    var row = crow.nextSiblings().first();
    // find elem
    if (!row) {
      // open new row
      if (crow.up('table').grid.add) {
        Grid.addRow(crow.up('table'), cell.up());
        row = crow.nextSiblings().first();
        var next = row.childElements()[0];
        setTimeout(function() {
          Grid.openCell(next);      
        }, 100);
      }
    } else {
       next = row.childElements()[pos];
       Grid.openCell(next);
    }
    event.stop();
  } else if ((false && key == 38) || (key == 13 && event.shiftKey)) {
    // up
    if (cell.childElements().first().tagName == 'SELECT' && event.shiftKey) {
      return
    }
    var row = cell.up();
    if (Grid.pos(row) == 1) {
      // stop
    } else {
      var pos = Grid.pos(cell);
      // move up
      row = row.previousSiblings().first();
      var next = row.childElements()[pos];
      Grid.openCell(next);
    }
    event.stop();
  }
  return false;
}

Grid.isReadOnly = function(cell) {
  return cell.select('a').length > 0 || cell.getAttribute('data-m') == 'r'
}

Grid.openCell = function(cell) {
  if (cell.hasClassName('input') || Grid.isReadOnly(cell)) return;
  var val = Grid.getValue(cell)
  cell.prev_value = val;

  var value = val.value
  var table = cell.up('table')

  if (table.grid.list_name) {
    if (value == 'on') {
      cell.setAttribute('data-v', 'off')
    } else {
      cell.setAttribute('data-v', 'on')
    }
    Grid.closeCell(cell)
  } else {
    var w = cell.getWidth() - 5
    var h = cell.getHeight() - 5
    cell.addClassName('input')
    
    // Try to find a form for the cell
    var input
    if (table.grid.helper && cell.tagName != 'TH') {
      var pos = Grid.pos(cell)
      input = table.grid.helper[pos]
      if (input) {
        input = Element.clone(input, true)
        cell.update(input)
        if (input.type == 'checkbox') {
          if (value == input.value) {
            input.checked = true
          }
        } else {
          if (value && value.strip() != '') input.value = value
        }
      }
    }
    
    if (!input) {
      // default input field
      cell.update(Grid.default_input)
      input = cell.childElements()[0]
      input.value = value
    }
    input.setStyle({
      width: w + 'px',
      height: h + 'px'
    })
    input.observe('blur', Grid.closeCell)
    input.observe('keydown', Grid.keydown)
    input.observe('paste', Grid.paste)
    input.focus()
    input.select()
  }
}

Grid.click = function(event) {
  var cell = event.findElement('td, th')
  var row = cell.up('tr')
  var table = cell.up('table')
  if (row.hasClassName('action')) {
    Grid.action(event, cell, row, true)
  } else if (cell.hasClassName('action')) {
    Grid.action(event, cell, row, false)
  } else if (cell.tagName == 'TH' && !table.grid.attr_name) {
    // sort
    Grid.sort(cell)
  } else {
    Grid.openCell(cell)
  }
}

Grid.valueFromInput = function(input) {
  var val = {}
  if (input.tagName == 'SELECT') {
    val.value = input.value
    val.show  = input.select('option[value="'+val.value+'"]').first().innerHTML
  } else {
    if (input.type == 'checkbox') {
      val.value = input.checked ? input.value : (input.getAttribute('data-off') || cell.getAttribute('data-v'))
    } else {
      val.value = input.value
    }
    val.show = val.value
  }
  return val
}

Grid.getValue = function(cell) {
  if (cell.hasClassName('input')) {
    return Grid.valueFromInput(cell.childElements()[0])
  }
  var val = {}
  val.show = cell.innerHTML
  val.value = cell.getAttribute('data-v') || val.show
  if (!cell.orig_value) cell.orig_value = val.value
  return val
}

Grid.copy = function(cell) {
  var table = cell.up('table')
  var row = cell.up()
  var pos = Grid.pos(cell)
  if (cell.tagName == 'TH') {
    row = row.nextSiblings()[0]
    cell = row.childElements()[pos]
  }
  var val = Grid.getValue(cell)

  table.grid.changes.push('start')
  Grid.changed(cell, val, cell.prev_value, true)
  cell.prev_value = val
  var rows = row.nextSiblings()
  var len = rows.length
  for (var i = 0; i < len; i++) {
    var c = rows[i].childElements()[pos]
    if (!Grid.isReadOnly(c)) {
      var prev = Grid.getValue(c)
      if (prev.value != val.value) Grid.changed(c, val, prev)
    }
  }
  table.grid.changes.push('end')
  if (table.grid.attr_name) {
    table.grid.input.value = Grid.serialize(table);
  }
}

Grid.addRow = function(table, row) {
  // insert row below
  var row_str = '<tr>';
  var cells = row.childElements();
  for (var i = 0; i < cells.length -1; i++) {
    row_str = row_str + '<td></td>';
  }
  row_str = row_str + Grid.Buttons(table.grid) + '</tr>';
  row.insert({
    after: row_str
  });
  var new_row = row.nextSiblings()[0];
  if (table.grid.attr_name) {
    // FIXME: rewrite history for undo
  } else {
    Grid.buildObj(table.grid, new_row)
  }
  return new_row
}

Grid.addCol = function(table, cell) {
  var rows = table.childElements()[0].select('tr');
  var pos = Grid.pos(cell);
  for (var i = 0; i < rows.length; i++) {
    var cells = rows[i].select('th');
    if (i == 0) {
      cells = rows[i].select('td');
      cells[pos].insert({
        after: Grid.ColButtons
      });
    } else if (cells.length > 0) {
      cells[pos].insert({
        after: "<th>[title]</th>"
      });
    } else {
      cells = rows[i].select('td');
      cells[pos].insert({
        after: "<td></td>"
      });
    }
  }
}

Grid.delCol = function(table, cell) {
  var rows = table.childElements()[0].select('tr');
  var pos = Grid.pos(cell);
  for (var i = 0; i < rows.length; i++) {
    var cells = rows[i].select('th');
    if (i == 0) {
      cells = rows[i].select('td');
      cells[pos].remove();
    } else if (cells.length > 0) {
      cells[pos].remove();
    } else {
      cells = rows[i].select('td');
      cells[pos].remove();
    }
  }
}

Grid.delRow = function(grid, row) {
  // remove current row
  if (!grid.attr_name) {
    // We must also clear the changes related to the removed row
    Grid.clearChanges(grid.changes, row.id)
  }
  row.remove();
}

Grid.action = function(event, cell, row, is_col) {
  var span = event.findElement('span')
  var table = event.findElement('table')
  var grid = table.grid
  if (span.hasClassName('add')) {
    if (is_col) {
      Grid.addCol(table, cell);
    } else {
      var new_row = Grid.addRow(table, row);
      Grid.openCell(new_row.childElements()[0]);
    }
  } else if (span.hasClassName('del')) {
    if (is_col) {
      Grid.delCol(table, cell);
    } else {
      if (event.altKey) {
        // remove current row and all unchanged below
        var rows = table.select('tr')
        var row_i  = Grid.pos(row)
        for(var i = rows.length - 1; i >= row_i; --i) {
          var arow = rows[i]
          if (!arow.hasClassName('changed')) Grid.delRow(grid, arow)
        }
      } else {
        Grid.delRow(grid, row)
      }
    }
  } else if (span.hasClassName('copy')) {
    var data = Grid.serialize(table, 'tab');
    var td = span.up();
    td.insert({
      top: "<textarea id='grid_copy_" + grid.id + "'></textarea>"
    });
    var input = $('grid_copy_'+grid.id);
    input.value = data;
    Element.observe($(input), 'blur', function(event) {
      event.element().remove();
    });
    input.focus();
    input.select();
  }
  if (grid.attr_name) {
    grid.input.value = Grid.serialize(table);
  }
}

// map grid position to attribute and reverse.
Grid.makeAttrPos = function(table) {
  var heads = table.select('th');
  var attr = {};
  var pos = {};
  var helper = {}
  var defaults = {}
  var helpers
  table.grid.attr = attr
  table.grid.pos = pos
  if (table.grid.helper_id) helpers = $(table.grid.helper_id)
  if (helpers) {
    table.grid.helper = helper;
  }
  if (table.grid.attr_name) {
    for (var i = 0; i < heads.length; i++) {
      attr[i] = i;
      pos[i] = i;
    }
  } else {
    for (var i = 0; i < heads.length; i++) {
      var attr_name = heads[i].getAttribute('data-a');
      attr[i] = attr_name;
      pos[attr_name] = i;
      if (helpers) {
        helper[i] = helpers.select('*[name="'+attr_name+'"]').first()
      }
    }
    // get default values
    if (helpers) {
      helpers.select('input,textarea,select').each(function(e) {
        if (e.getAttribute('data-d') == 'true') {
          defaults[e.name] = Grid.valueFromInput(e)
        }
      })  
    }
  }
  table.grid.defaults = $H(defaults)
}

// only used with single attr table
Grid.serialize = function(table, format) {
  var data = [];
  var rows = table.childElements()[0].select('tr');
  for (var i = 1; i < rows.length; i++) {
    var row_data = [];
    var cells = rows[i].childElements();
    for (var j = 0; j < cells.length - 1; j++) {
      var cell = cells[j];
      if (cell.hasClassName('input')) {
        row_data.push(cell.childElements()[0].value)
      } else {
        row_data.push(cell.innerHTML)
      }
    }
    data.push(row_data);
  }
  if (format == 'tab') {
    var res = '';
    for (var i = 0; i < data.length; i++) {
      var row = data[i];
      var line = '';
      for (var j=0; j < row.length; j++) {
        if (j>0) line = line + '\t';
        line = line + row[j];
      }
      if (i>0) res = res + '\r\n';
      res = res + line;
    }
    return res;
  } else if (data.length == 1 && data[0].length == 1) {
    return '';
  } else {
    return Object.toJSON([{type:'table'}, data]);
  }
}

Grid.Buttons = function(grid) {
  var btns = "<td class='action'>"
  if (grid.add) btns = btns + "<span class='add'>&nbsp;</span>"
  if (grid.remove) btns = btns + "<span class='del'>&nbsp;</span>"
  btns = btns + "</td>"
  return btns
}

Grid.ColButtons = "<td><span class='del'>&nbsp;</span> <span class='add'>&nbsp;</span></td>"

// only used with single attr table
Grid.addButtons = function(table) {
  var grid = table.grid
  var attr_table = grid.attr_name
  var data = []
  var tbody = table.childElements()[0]
  var rows = tbody.select('tr')

  if (attr_table) {
    var col_action = "<tr class='action'><td><span class='add'>&nbsp;</span></td>";
    var cells_length = rows[0].select('th').length;
    for (var i = 1; i < cells_length; i++) {
      col_action = col_action + Grid.ColButtons;
    }
    col_action = col_action + "<td class='action'><span class='copy'>&nbsp;</span></td></tr>";
  }

  for (var i = 0; i < rows.length; i++) {
    var buttons
    if (i == 0) {
      if (grid.add) {
        buttons = "<td class='action'><span class='add'>&nbsp;</span></td>"
      } else {
        buttons = "<td class='action'></td>"
      }
    } else {
      buttons = Grid.Buttons(grid)
    }
    rows[i].insert({
      bottom: buttons
    })
  }
  tbody.insert({
    top: col_action
  })
  return data
}

Grid.onFailure = function(grid, id, errors) {
  var cells = $(id).select('td')
  errors.each(function(pair) {
    var pos = grid.pos[pair.key] || -1
    var cell = cells[pos]
    if (cell) {
      Grid.setError(cell, pair.value)
    } else {
      // generic error
      Grid.setError($(id), pair.key + ': ' + pair.value)
    }
  })
}

Grid.setError = function(e, msg) {
  if (!Grid.msg) {
    Grid.msg = $('grid_msg_')
    if (!Grid.msg) {
      $(document.body).insert({
        bottom: "<div id='grid_msg_' style='display:none' class='grid_msg'></div>"
      })
      Grid.msg = $('grid_msg_')
    }
    Grid.msg.absolutize()
  }
  e.observe('mouseover', function() {
    Grid.msg.innerHTML = msg
    Element.clonePosition(Grid.msg, e, {
      setWidth:false,
      setHeight:false,
      offsetTop:3,
      offsetLeft:e.getWidth() - 3,
    })
    Grid.msg.show()
  })
  e.observe('mouseout', function() {
    Grid.msg.hide()
  })
  e.addClassName('error')
}

Grid.make = function(table, opts) {
  opts = opts || {}
  table = $(table)
  if (table.grid) return;
  Grid.grid_c++;
  Grid.grids[Grid.grid_c] = table;
  table.grid = {
    changes: [],
    id: Grid.grid_c,
    helper_id: table.getAttribute('data-helper'),
    fdate: table.getAttribute('data-fdate'),
    counter: 0, // Used to create dom_ids for new objects
    onSuccess: opts.onSuccess,
    onFailure: opts.onFailure || Grid.onFailure,
    onStart: opts.onStart || Grid.onStart,
    add: opts.add || opts.add == undefined,
    remove: opts.remove || opts.remove == undefined,
    keydown: opts.keydown,
  };
  
  // Detect type.
  table.grid.attr_name = table.getAttribute('data-a');
  table.grid.list_name = table.getAttribute('data-l');

  var empty = false;
  if (table.grid.attr_name && table.select('th').length == 0) {
    empty = true;
    var msg = table.getAttribute('data-msg') || "type to edit";
    table.innerHTML = "<tr><th>" + msg + "</th></tr><tr><td></td></tr>";
  }
  
  Grid.makeAttrPos(table)
  Grid.addButtons(table)
  

  if (table.grid.attr_name) {
    // If we have an attr_name, rows and columns are
    // serialized as json in a single field.
    table.insert({
      after: "<input type='hidden' id='grid_a_" + Grid.grid_c + "' name='" + table.grid.attr_name + "'/>"
    });
    table.grid.input = $("grid_a_" + Grid.grid_c);
    if (!empty) table.grid.input.value = Grid.serialize(table);
  } else {
    var rows = table.select('tr')
    for (var i = 1; i < rows.length; i++) {
      if (!rows[i].id) {
        Grid.buildObj(table.grid, rows[i])
      }
    }
    // Otherwise each row is a new object and each column
    // corresponds to a different attribute (defined in the 
    // 'th' of the table).
    table.insert({
      after: "<p class='grid_btn'><a class='save' href='javascript:' onclick='Grid.save(" + Grid.grid_c + ")'>save</a> <a class='undo' href='javascript:' onclick='Grid.undo(" + Grid.grid_c + ")'>undo</a></p>"
    });
  }

  table.observe('click', Grid.click);
}

// Default onStart handler
Grid.onStart = function(operations) {
  if (operations.post) {
    return confirm('Create '+operations.post+' nodes ?')
  }
  return true
}

Grid.clearChanges = function(list, id) {
  for (var i = list.length - 1; i >= 0; i--) {
    while (list[i] && list[i].id == id) {
      list.splice(i, 1)
    }
  }
}

Grid.isChanged = function(elem) {
  var table = $(elem)
  var grid = table.grid
  // buildObj adds a row per new object on load
  return grid.changes.length > (table.attr_name ? 0 : table.select('tr').length - 1)
}


Grid.save = function(grid_id) {
  // do not run on GUI thread
  setTimeout(function() {
    var table = Grid.grids[grid_id]
    var grid  = table.grid
    var data  = Grid.compact(grid.changes)
    if (grid.list_name) {
      data = Grid.dataForList(grid, data)
    }
    var todo_count = data.keys().length
    var done_count = 0
    if (grid.onStart) {
      var operations = {}
      data.each(function(pair) {
        if (pair.value._new) {
          operations.post = (operations.post || 0) + 1
        } else {
          operations.put = (operations.put || 0) + 1
        }
      })
      if (!grid.onStart(operations)) return
    }
    data.each(function(pair) {
      var id = pair.key
      var changes = pair.value
      var attrs = {zjs:true, "opts[format]":grid.fdate}
      $H(changes).each(function(pair) {
        if (pair.key != '_new') {
          attrs['node['+pair.key+']'] = pair.value
        }
      })
      if (changes._new) {
        new Ajax.Request('/nodes', {
          parameters: attrs,
          onSuccess: function(transport) {
            done_count++
            var reply = transport.responseText.evalJSON()
            // Change row id: it is no longer a new item
            var old_id = id
            $(id).id = 'id_' + reply.id
            id = 'id_' + reply.id
            var attrs = {}
            attrs[id] = reply
            Grid.notify(table, attrs)
            Grid.clearChanges(grid.changes, old_id)
            if (grid.onSuccess) {
              grid.onSuccess(grid, id, 'post', done_count, todo_count)
            }
          },

          onFailure: function(transport) {
            done_count++
            var errors = {}
            transport.responseText.evalJSON().each(function(e) {
              errors[e[0]] = e[1]
            })
            // Change row id: it is no longer a new item
            grid.onFailure(grid, id, $H(errors))
          },
          method: 'post'
        });
      } else {
        new Ajax.Request('/nodes/' + id.replace('id_',''), {
          parameters: attrs,
          onSuccess: function(transport) {
            done_count++
            var attrs = {}
            attrs[id] = transport.responseText.evalJSON()
            Grid.notify(table, attrs)
            Grid.clearChanges(grid.changes, id)
            if (grid.onSuccess) {
              grid.onSuccess(id, 'put', done_count, todo_count)
            }
          },
          method: 'put'
        });
      }
    })
  }, 100);
}

Grid.undo = function(grid_id, skip_undone) {
  var table = Grid.grids[grid_id]
  var grid = table.grid
  var changes = grid.changes
  var last = changes.last()
  if (!last || last._new) return
  var group = false
  if (last == 'end') {
    group = true
    changes.pop()
  }
  var change = changes.pop()
  var old = change._old
  for (attr in change) {
    if (attr == 'id' || attr == '_old') continue
    var cell = $(change.id).childElements()[grid.pos[attr]]
    var val  = old
    var value = old.value
    cell.innerHTML = val.show || ''
    cell.prev_value = val
    if (value == cell.orig_value) {
      cell.removeClassName('changed')
      var row = cell.up()
      if (row.select('.changed').length == 0) row.removeClassName('changed')
    } else {
      [cell, cell.up()].invoke('addClassName', 'changed')
    }
    cell.addClassName('undone')
    if (grid.list_name) {
      cell.setAttribute('data-v', value)
      if (value == 'on') {
        cell.addClassName('on')
      } else {
        cell.removeClassName('on')
      }
    }
  }
  if (group) {
    while (changes.last() != 'start') {
      Grid.undo(grid_id, true)
    }
    changes.pop()
  }

  if (!skip_undone) {
    setTimeout(function() {
      table.select('.undone').invoke('removeClassName', 'undone')
    }, 1000)
  }
}

Grid.compact = function(list) {
  var res = {};
  for (var i = list.length - 1; i >= 0; i--) {
    var changes = list[i];
    if (typeof(changes) == 'string') continue
    var obj = res[changes.id];
    if (!obj) {
      obj = {};
      res[changes.id] = obj;
    }

    for (var key in changes) {
      if (key != 'id' && key != '_old' && !obj[key]) {
        // only take latest change
        obj[key] = changes[key].value;
      }
    }
  }
  return $H(res);
}

Grid.test = function() {
  var grid = $('grid').grid
  var data = Grid.compact(grid.changes)
  return Grid.dataForList(grid, data)
}

// Build the changes array when we have a list. This function
// detects which rows have changes and builds the full list of
// ids in the format some_relation_ids:"123,345,888,432". Other fields
// are kept as is.
Grid.dataForList = function(grid, data) {
  var res = {}
  var list_name = grid.list_name
  data.each(function(pair) {
    var obj = {}
    var base = pair.value
    res[pair.key] = obj
    for (var key in base) {
      if (parseInt(key) + '' == key) {
        // number key = there is a change in the list
        if (!obj[list_name]) {
          // build full list
          var list = []
          var row = $(pair.key)
          var cells = row.childElements()
          for (var i = 0; i < cells.length - 1; i++) {
            var cell = cells[i]
            var attr = grid.attr[i]
            if (attr && (parseInt(attr) + '' == attr)) {
              // number attr key
              if (cell.getAttribute('data-v') == 'on') list.push(attr)
            }
          }
          obj[list_name] = list.join(',')
        }
      } else {
        // keep other attributes unchanged
        obj[key] = base[key]
      }
    }
  })
  return $H(res)
}

Grid.notify = function(table, changes) {
  var rows = table.childElements()[0].select('tr')
  var grid = table.grid
  var pos = grid.pos
  for (var obj_id in changes) {
    var row
    if (grid.attr_name) {
      // attr table
      row = rows[parseInt(obj_id)+1]
    } else {
      row = $(obj_id)
    }
    var cells = row.childElements()
    var change = changes[obj_id]
    for (var attr in change) {
      if (attr == 'id') continue
      if (attr == grid.list_name) {
        var list_on = change[attr].split(/,/)
        var cells = row.childElements()
        for (var i = 0; i < cells.length - 1; i++) {
          var attr = grid.attr[i]
          var cell = cells[i]
          if (parseInt(attr) + '' == attr) {
            if (list_on.indexOf(attr) >= 0) {
              cell.orig_value = 'on'
              cell.setAttribute('data-v', 'on')
            } else {
              cell.orig_value = 'off'
              cell.setAttribute('data-v', 'off')
            }
            cell.prev_value = undefined
            cell.removeClassName('error')
            cell.removeClassName('changed')
            cell.addClassName('saved')
          }
        }
      } else {
        var cell
        var i = pos[attr]
        if (i == undefined) continue
        cell = cells[i]
        cell.removeClassName('changed')
        cell.removeClassName('error')
        if (cell.getAttribute('data-v') != change[attr]) {
          cell.innerHTML = change[attr]
        }
        cell.orig_value = change[attr]
        cell.prev_value = undefined
        cell.addClassName('saved')
      }
    }
    row.removeClassName('new')
    row.removeClassName('error')
    if (row.select('.changed').length == 0) {
      row.removeClassName('changed')
    }
  }
  // later
  setTimeout(function() {
    table.select('.saved').invoke('removeClassName', 'saved')
  }, 1000)
}

Grid.simulateClick = function(l) {
  if (document.createEvent) {
    var e = document.createEvent('MouseEvents')
    e.initMouseEvent('click', true, true, document.defaultView, 0, 0, 0, 0, 0, false, false, false, false, 0, l)
    l.dispatchEvent(e)
  } else {
    var e = Object.extend(document.createEventObject())
    l.fireEvent('onclick', e)
  }
}

Grid.sort = function(cell) {
  var table = cell.up('table')
  var desc = false
  if (cell.hasClassName('asc')) {
    desc = true
    cell.removeClassName('asc')
    cell.addClassName('desc')
  } else {
    table.select('.asc, .desc').each(function(e) { e.removeClassName('asc').removeClassName('desc') })
    cell.addClassName('asc')
  }
  var body = table.childElements()[0]
  var rows = body.select('tr')
  rows.splice(0,1)
  var col_i = Grid.pos(cell)

  rows.sort(function(a, b) {
    var atxt = a.childElements()[col_i].innerHTML.stripTags().toLowerCase()
    var btxt = b.childElements()[col_i].innerHTML.stripTags().toLowerCase()
    return atxt.localeCompare(btxt) * (desc ? -1 : 1)
  }).each(Element.prototype.appendChild, body)
}       

/////////// Tags
Tags = {}

Tags.click = function(event) {
  var e = event.element()
  var value = e.getAttribute('data-v') || e.innerHTML
  var tags = e.tags
  var list = tags.list
  for (var i = list.length - 1; i >= 0; i--) {
    while (list[i] && list[i] == value) {
      list.splice(i, 1)
    }
  }
  tags.onChange(list, e)
}

Tags.add = function(event) {
  var e = event.element()
  var value = e.value
  var tags = e.tags
  var list = tags.list
  for (var i = list.length - 1; i >= 0; i--) {
    while (list[i] && list[i] == value) {
      list.splice(i, 1)
    }
  }
  list.push(value)
  tags.onChange(list)
}

Tags.make = function(elem, opts) {
  var tags = {}
  tags.onChange = opts.onChange
  elem.tags = tags
  var list = []
  tags.list = list
  elem.childElements().each(function(e) {
    var input = e.select('input,select').first()
    if (input) {
      input.tags = tags
      input.observe('change', Tags.add)
    } else {
      e.tags = tags
      list.push(e.getAttribute('data-v') || e.innerHTML)
      e.observe('click', Tags.click)
    }
  })
}


