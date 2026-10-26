--[[============================================================================
Transposition Shortcut Bar

A small floating bar of note transposition shortcuts for the pattern editor:
+1, -1, +12, -12 and two variable +N / -N buttons. Each button transposes the
notes in the current pattern selection, like the pattern editor's right-click
"Selection > Transpose Notes ..." entries.
============================================================================]]--

local TOOL_NAME = "Transposition Shortcut Bar"

local N_MIN = 1
local N_MAX = 24
local N_DEFAULT = 3

local NOTE_MIN = 0    -- C-0
local NOTE_MAX = 119  -- B-9

local BUTTON_WIDTH = 28
local VALUEBOX_WIDTH = 48


--------------------------------------------------------------------------------
-- Preferences (stored in the tool's preferences.xml, so they persist across
-- songs and Renoise sessions)

local prefs = renoise.Document.create("TranspositionShortcutBarPreferences") {
  show_bar = true,
  up_semitones = N_DEFAULT,
  down_semitones = N_DEFAULT,
}

renoise.tool().preferences = prefs


--------------------------------------------------------------------------------
-- Helpers

local function clamp(value, min_value, max_value)
  return math.max(min_value, math.min(max_value, value))
end

local function semitones_text(amount)
  return (amount == 1) and "semitone" or "semitones"
end

local function current_n(preference)
  return clamp(math.floor(preference.value), N_MIN, N_MAX)
end

local function is_edit_screen()
  return renoise.app().window.active_middle_frame ==
    renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
end

-- Tool windows take keyboard focus away from the pattern editor when they are
-- clicked. Toggling lock_keyboard_focus twice hands focus back to the middle
-- frame while leaving the user's own lock setting untouched.
local function refocus_pattern_editor()
  local window = renoise.app().window
  window.lock_keyboard_focus = not window.lock_keyboard_focus
  window.lock_keyboard_focus = not window.lock_keyboard_focus
end


--------------------------------------------------------------------------------
-- Transposition

-- Transposes all notes in the current pattern selection by the given amount
-- of semitones. Note-offs and empty notes are left alone, and notes are
-- clamped to the valid C-0..B-9 range.
local function transpose_selection(semitones)
  local song = renoise.song()
  if not song then
    return
  end

  local selection = song.selection_in_pattern
  if not selection then
    renoise.app():show_status(TOOL_NAME .. ": Nothing selected in the pattern editor.")
    return
  end

  local pattern = song.selected_pattern
  local start_line = selection.start_line or 1
  local end_line = math.min(selection.end_line or pattern.number_of_lines,
    pattern.number_of_lines)
  local start_track = selection.start_track or 1
  local end_track = math.min(selection.end_track or #song.tracks, #song.tracks)

  -- collect changes first: the undo description must be set before the song
  -- is modified, and only when something actually changes
  local columns = {}
  local new_values = {}

  for track_index = start_track, end_track do
    local visible_note_columns = song:track(track_index).visible_note_columns
    if visible_note_columns > 0 then
      local lines = pattern:track(track_index):lines_in_range(start_line, end_line)
      for _, line in ipairs(lines) do
        if not line.is_empty then
          for column_index = 1, visible_note_columns do
            local column = line:note_column(column_index)
            local note = column.note_value
            if column.is_selected and note < renoise.PatternLine.NOTE_OFF then
              local new_note = clamp(note + semitones, NOTE_MIN, NOTE_MAX)
              if new_note ~= note then
                columns[#columns + 1] = column
                new_values[#new_values + 1] = new_note
              end
            end
          end
        end
      end
    end
  end

  local direction = (semitones > 0) and "Up" or "Down"
  local amount = math.abs(semitones)

  if #columns == 0 then
    renoise.app():show_status(("%s: No notes to transpose %s in the selection.")
      :format(TOOL_NAME, direction:lower()))
    return
  end

  song:describe_undo(("Transpose Notes %s %d"):format(direction, amount))
  for index, column in ipairs(columns) do
    column.note_value = new_values[index]
  end

  renoise.app():show_status(("%s: Transposed %d note(s) %s by %d %s.")
    :format(TOOL_NAME, #columns, direction:lower(), amount, semitones_text(amount)))
end


--------------------------------------------------------------------------------
-- Bar dialog

local dialog = nil
local up_n_button = nil
local down_n_button = nil
local document_loaded = false

local function update_variable_buttons()
  if up_n_button then
    local n = current_n(prefs.up_semitones)
    up_n_button.text = ("+%d"):format(n)
    up_n_button.tooltip = ("Transposes notes up by %d %s"):format(n, semitones_text(n))
  end
  if down_n_button then
    local n = current_n(prefs.down_semitones)
    down_n_button.text = ("-%d"):format(n)
    down_n_button.tooltip = ("Transposes notes down by %d %s"):format(n, semitones_text(n))
  end
end

local function build_bar()
  local vb = renoise.ViewBuilder()

  local function shortcut_button(label, tooltip, semitones)
    return vb:button {
      text = label,
      tooltip = tooltip,
      width = BUTTON_WIDTH,
      notifier = function()
        transpose_selection(semitones)
        refocus_pattern_editor()
      end
    }
  end

  -- a button glued to a 1..24 valuebox, so both read as one control
  local function variable_shortcut(sign, preference)
    local button = vb:button {
      width = BUTTON_WIDTH,
      style = "rounded_left",
      notifier = function()
        transpose_selection(sign * current_n(preference))
        refocus_pattern_editor()
      end
    }
    local control = vb:row {
      spacing = 0,
      button,
      vb:valuebox {
        width = VALUEBOX_WIDTH,
        min = N_MIN,
        max = N_MAX,
        bind = preference,
        tooltip = "Number of semitones (1-24)",
      }
    }
    return control, button
  end

  local up_n_control, down_n_control
  up_n_control, up_n_button = variable_shortcut(1, prefs.up_semitones)
  down_n_control, down_n_button = variable_shortcut(-1, prefs.down_semitones)
  update_variable_buttons()

  return vb:row {
    margin = renoise.ViewBuilder.DEFAULT_CONTROL_MARGIN,
    spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING,
    shortcut_button("-1", "Transposes notes down by 1 semitone", -1),
    shortcut_button("+1", "Transposes notes up by 1 semitone", 1),
    shortcut_button("-12", "Transposes notes down by 12 semitones", -12),
    shortcut_button("+12", "Transposes notes up by 12 semitones", 12),
    down_n_control,
    up_n_control,
  }
end

-- pass all keys back to Renoise, so global shortcuts keep working while the
-- bar has focus
local function key_handler(_, key)
  return key
end

local function show_bar()
  if dialog and dialog.visible then
    return
  end
  dialog = renoise.app():show_custom_dialog(TOOL_NAME, build_bar(), key_handler)
  refocus_pattern_editor()
end

local function hide_bar()
  if dialog and dialog.visible then
    dialog:close()
  end
  dialog = nil
  up_n_button = nil
  down_n_button = nil
end

local function update_visibility()
  if document_loaded and prefs.show_bar.value and is_edit_screen() then
    show_bar()
  else
    hide_bar()
  end
end

local function toggle_bar()
  prefs.show_bar.value = not prefs.show_bar.value
  update_visibility()
  if prefs.show_bar.value and not is_edit_screen() then
    renoise.app():show_status(TOOL_NAME .. ": Enabled. It shows on the Edit screen.")
  end
end

local function show_bar_from_menu()
  prefs.show_bar.value = true
  renoise.app().window.active_middle_frame =
    renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
  update_visibility()
end

local function hide_bar_from_menu()
  prefs.show_bar.value = false
  update_visibility()
end


--------------------------------------------------------------------------------
-- Tools menu entry, labeled "Show ..." or "Hide ..." depending on whether the
-- bar is currently visible. Menu labels can't be renamed, so the entry is
-- swapped out whenever the visibility changes.

local TOOLS_MENU_PATH = "Main Menu:Tools:" .. TOOL_NAME .. ":"
local tools_menu_entry = nil

local function update_tools_menu()
  local bar_visible = (dialog ~= nil and dialog.visible)
  local name = TOOLS_MENU_PATH .. (bar_visible and "Hide " or "Show ") .. TOOL_NAME
  if name == tools_menu_entry then
    return
  end
  if tools_menu_entry and renoise.tool():has_menu_entry(tools_menu_entry) then
    renoise.tool():remove_menu_entry(tools_menu_entry)
  end
  renoise.tool():add_menu_entry {
    name = name,
    invoke = bar_visible and hide_bar_from_menu or show_bar_from_menu
  }
  tools_menu_entry = name
end


--------------------------------------------------------------------------------
-- Notifiers

-- sanitize values from hand-edited preference files once they are loaded
renoise.tool().tool_finished_loading_observable:add_notifier(function()
  prefs.up_semitones.value = current_n(prefs.up_semitones)
  prefs.down_semitones.value = current_n(prefs.down_semitones)
end)

prefs.up_semitones:add_notifier(update_variable_buttons)
prefs.down_semitones:add_notifier(update_variable_buttons)

renoise.tool().app_new_document_observable:add_notifier(function()
  document_loaded = true
  local frame_observable = renoise.app().window.active_middle_frame_observable
  if not frame_observable:has_notifier(update_visibility) then
    frame_observable:add_notifier(update_visibility)
  end
  update_visibility()
end)

renoise.tool().app_release_document_observable:add_notifier(function()
  document_loaded = false
end)

-- When the user closes the bar's window themself, keep it closed until it is
-- enabled again via the menu or the keybinding. The Tools menu label is also
-- synced here, rather than from within a menu entry's own invoke callback.
renoise.tool().app_idle_observable:add_notifier(function()
  if dialog and not dialog.visible and document_loaded then
    dialog = nil
    up_n_button = nil
    down_n_button = nil
    prefs.show_bar.value = false
  end
  update_tools_menu()
end)


--------------------------------------------------------------------------------
-- Menu entries and keybindings

renoise.tool():add_menu_entry {
  name = "Main Menu:View:" .. TOOL_NAME,
  selected = function() return prefs.show_bar.value end,
  invoke = toggle_bar
}

update_tools_menu()

renoise.tool():add_keybinding {
  name = "Global:Tools:Toggle " .. TOOL_NAME,
  invoke = function(repeated)
    if not repeated then
      toggle_bar()
    end
  end
}

-- ±N shortcuts, using the bar's current N values. Renoise does not allow tools
-- to define default keys, so these are unassigned until set in Preferences > Keys.
renoise.tool():add_keybinding {
  name = "Pattern Editor:" .. TOOL_NAME .. ":Transpose Notes Down N",
  invoke = function()
    transpose_selection(-current_n(prefs.down_semitones))
  end
}

renoise.tool():add_keybinding {
  name = "Pattern Editor:" .. TOOL_NAME .. ":Transpose Notes Up N",
  invoke = function()
    transpose_selection(current_n(prefs.up_semitones))
  end
}
