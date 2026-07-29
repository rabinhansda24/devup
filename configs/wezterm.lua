-- ~/.wezterm.lua — installed by devup.
-- devup:wezterm — delete this marker line to take ownership of this file
-- (devup will then leave it alone instead of updating it).

local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

--------------------------------------------------------------------------------
-- Appearance
--------------------------------------------------------------------------------
config.color_scheme = 'Catppuccin Mocha'
config.font = wezterm.font_with_fallback {
  { family = 'JetBrainsMono Nerd Font', weight = 'Regular' },
  'DejaVu Sans Mono',
}
config.font_size = 11.5
config.line_height = 1.1

config.window_padding = { left = 8, right = 8, top = 8, bottom = 0 }

-- Keep the window's own title bar, so minimise / maximise / close are there.
-- 'RESIZE' alone gives a borderless window you cannot close with the mouse.
config.window_decorations = 'TITLE | RESIZE'

-- Always show the tab bar. Hiding it on a single tab means a new user never
-- discovers tabs exist. The *fancy* bar is the one that draws a × on each tab
-- and a + to add one — the retro bar has neither, which is why the tab controls
-- appeared to be missing. Fancy always renders at the top, so no bottom option.
config.hide_tab_bar_if_only_one_tab = false
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.tab_max_width = 32

config.scrollback_lines = 20000
config.audible_bell = 'Disabled'

--------------------------------------------------------------------------------
-- Wayland
--------------------------------------------------------------------------------
-- Ubuntu defaults to Wayland. WezTerm's Wayland support is good, but if you hit
-- blurry text, cursor glitches or resize weirdness, flip this to false to force
-- XWayland.
config.enable_wayland = true

--------------------------------------------------------------------------------
-- Performance
--------------------------------------------------------------------------------
config.front_end = 'WebGpu'          -- fall back to 'OpenGL' on older iGPUs
config.webgpu_power_preference = 'LowPower'  -- laptop battery
config.max_fps = 60

--------------------------------------------------------------------------------
-- Keys: leader is Ctrl-Shift-A, tmux-style.
--
-- Not Ctrl-A: that is readline's beginning-of-line, and making it the leader
-- taxes every single use of it with the leader timeout. A terminal cannot encode
-- Ctrl-Shift-<letter>, so binding it costs the shell nothing.
--
-- Tabs also work with the WezTerm defaults, which are left untouched:
--   Ctrl-Shift-T       new tab
--   Ctrl-Shift-W       close tab
--   Ctrl-Tab           next tab
-- ...or just click the + and × on the tab bar.
--
--   LEADER -           split horizontally (side by side)
--   LEADER |           split vertically (stacked)
--   LEADER h/j/k/l     move between panes
--   LEADER H/J/K/L     resize the active pane
--   LEADER z           zoom the active pane fullscreen
--   LEADER x           close the active pane
--   LEADER c           new tab
--   LEADER n / p       next / previous tab
--   LEADER 1-9         jump to tab N
--   LEADER f           fuzzy-search the scrollback
--   LEADER [           copy mode (vim keys, then y to yank)
--------------------------------------------------------------------------------
config.leader = { key = 'a', mods = 'CTRL|SHIFT', timeout_milliseconds = 1000 }

config.keys = {
  -- Splits
  { key = '-', mods = 'LEADER', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '|', mods = 'LEADER|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = '\\', mods = 'LEADER', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },

  -- Pane navigation
  { key = 'h', mods = 'LEADER', action = act.ActivatePaneDirection 'Left' },
  { key = 'j', mods = 'LEADER', action = act.ActivatePaneDirection 'Down' },
  { key = 'k', mods = 'LEADER', action = act.ActivatePaneDirection 'Up' },
  { key = 'l', mods = 'LEADER', action = act.ActivatePaneDirection 'Right' },

  -- Pane resize
  { key = 'H', mods = 'LEADER|SHIFT', action = act.AdjustPaneSize { 'Left', 5 } },
  { key = 'J', mods = 'LEADER|SHIFT', action = act.AdjustPaneSize { 'Down', 5 } },
  { key = 'K', mods = 'LEADER|SHIFT', action = act.AdjustPaneSize { 'Up', 5 } },
  { key = 'L', mods = 'LEADER|SHIFT', action = act.AdjustPaneSize { 'Right', 5 } },

  { key = 'z', mods = 'LEADER', action = act.TogglePaneZoomState },
  { key = 'x', mods = 'LEADER', action = act.CloseCurrentPane { confirm = true } },

  -- Tabs
  { key = 'c', mods = 'LEADER', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'n', mods = 'LEADER', action = act.ActivateTabRelative(1) },
  { key = 'p', mods = 'LEADER', action = act.ActivateTabRelative(-1) },

  -- Search and copy mode
  { key = 'f', mods = 'LEADER', action = act.Search { CaseInSensitiveString = '' } },
  { key = '[', mods = 'LEADER', action = act.ActivateCopyMode },

  -- Font size
  { key = '=', mods = 'CTRL', action = act.IncreaseFontSize },
  { key = '-', mods = 'CTRL', action = act.DecreaseFontSize },
  { key = '0', mods = 'CTRL', action = act.ResetFontSize },

  -- Quick config reload
  { key = 'r', mods = 'LEADER|SHIFT', action = act.ReloadConfiguration },
}

-- LEADER 1-9 jumps straight to a tab.
for i = 1, 9 do
  table.insert(config.keys, {
    key = tostring(i),
    mods = 'LEADER',
    action = act.ActivateTab(i - 1),
  })
end

--------------------------------------------------------------------------------
-- Show the leader key state in the status area, so you can tell when WezTerm
-- is waiting for the second half of a chord.
--------------------------------------------------------------------------------
wezterm.on('update-right-status', function(window, _)
  local prefix = ''
  if window:leader_is_active() then
    prefix = ' LEADER '
  end
  window:set_right_status(wezterm.format {
    { Foreground = { Color = '#f38ba8' } },
    { Text = prefix },
  })
end)

return config
