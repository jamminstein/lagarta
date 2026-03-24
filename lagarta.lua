-- lagarta
-- ciat-lonbarde for norns
--
-- peter blasser's chaos in code
-- bounds | clicks | gongs
--
-- E1 page
-- E2/E3 per-page controls
-- K2 manual click
-- K3 chaos burst
--
-- pages:
--  QUANTUSSY  5-osc ring
--  CLICKER    impulse + ring mod
--  GONGS      resonant bodies
--
-- v1.0 @jamminstein

engine.name = "Lagarta"

local musicutil = require "musicutil"

------------------------------------------------------------
-- constants
------------------------------------------------------------

local PAGES = {"QUANTUSSY", "CLICKER", "GONGS"}
local DIV_NAMES = {"1", "1/2", "1/3", "1/4", "1/6", "1/8", "1/12", "1/16"}
local DIV_VALUES = {1, 1/2, 1/3, 1/4, 1/6, 1/8, 1/12, 1/16}

local scale_names = {}
for i = 1, #musicutil.SCALES do
  scale_names[i] = musicutil.SCALES[i].name
end

------------------------------------------------------------
-- state
------------------------------------------------------------

local page = 1
local frame = 0

-- visual
local click_flash = 0
local gong_rings = {0, 0, 0, 0}
local q_phase = {0, 0, 0, 0, 0}
local q_wobble = {0, 0, 0, 0, 0}
local chaos_burst = 0

-- music mode
local scale_notes = {}
local note_index = 1
local held_notes = {}

-- explorer
local explorer_active = false
local explorer_clock_id = nil

-- midi
local midi_out = nil

------------------------------------------------------------
-- init
------------------------------------------------------------

function init()
  -- GLOBAL
  params:add_separator("header", "LAGARTA")
  params:add_group("global", "GLOBAL", 4)

  params:add_control("chaos", "chaos",
    controlspec.new(0, 1, 'lin', 0, 0.3))
  params:add_control("drift", "drift",
    controlspec.new(0, 1, 'lin', 0, 0.1))
  params:add_control("amp", "amplitude",
    controlspec.new(0, 1, 'lin', 0, 0.5))
  params:add_option("explorer", "explorer", {"off", "on"}, 1)

  params:set_action("chaos", function(v) engine.chaos(v) end)
  params:set_action("drift", function(v) engine.drift(v) end)
  params:set_action("amp", function(v) engine.amp(v) end)
  params:set_action("explorer", function(v) toggle_explorer(v == 2) end)

  -- QUANTUSSY
  params:add_group("quantussy", "QUANTUSSY", 9)

  local q_freqs = {55, 82, 131, 196, 330}
  for i = 1, 5 do
    local id = "q_freq" .. i
    params:add_control(id, "osc " .. i .. " freq",
      controlspec.new(20, 2000, 'exp', 0, q_freqs[i], "hz"))
    params:set_action(id, function(v) engine[id](v) end)
  end

  params:add_control("q_cross", "cross mod",
    controlspec.new(0, 1, 'lin', 0, 0.3))
  params:add_control("q_fold", "wavefold",
    controlspec.new(0, 1, 'lin', 0, 0.5))
  params:add_control("q_bounds", "bounds",
    controlspec.new(0.05, 1, 'lin', 0, 0.5))
  params:add_control("q_mix", "quantussy mix",
    controlspec.new(0, 1, 'lin', 0, 0.5))

  params:set_action("q_cross", function(v) engine.q_cross(v) end)
  params:set_action("q_fold", function(v) engine.q_fold(v) end)
  params:set_action("q_bounds", function(v) engine.q_bounds(v) end)
  params:set_action("q_mix", function(v) engine.q_mix(v) end)

  -- CLICKER
  params:add_group("clicker", "CLICKER", 9)

  params:add_control("click_rate", "rate",
    controlspec.new(0.1, 40, 'exp', 0, 3, "hz"))
  params:add_control("click_decay", "decay",
    controlspec.new(0.001, 0.5, 'exp', 0, 0.008, "s"))
  params:add_control("click_pitch", "pitch",
    controlspec.new(100, 8000, 'exp', 0, 800, "hz"))
  params:add_control("click_ring", "ring mod",
    controlspec.new(0, 1, 'lin', 0, 0.5))
  params:add_control("click_amp", "click level",
    controlspec.new(0, 1, 'lin', 0, 0.5))
  params:add_option("click_sync", "sync", {"free", "clock"}, 1)
  params:add_option("click_div", "division", DIV_NAMES, 4)
  params:add_option("music_mode", "music mode", {"off", "on"}, 1)
  params:add_option("scale", "scale", scale_names, 1)

  params:set_action("click_rate", function(v) engine.click_rate(v) end)
  params:set_action("click_decay", function(v) engine.click_decay(v) end)
  params:set_action("click_pitch", function(v) engine.click_pitch(v) end)
  params:set_action("click_ring", function(v) engine.click_ring(v) end)
  params:set_action("click_amp", function(v) engine.click_amp(v) end)
  params:set_action("click_sync", function(v)
    engine.click_free(v == 1 and 1 or 0)
  end)
  params:set_action("scale", function() update_scale() end)

  -- GONGS
  params:add_group("gongs", "GONGS", 6)

  local gf = {400, 633, 1048, 1672}
  for i = 1, 4 do
    local id = "gong" .. i
    params:add_control(id, "gong " .. i .. " freq",
      controlspec.new(50, 5000, 'exp', 0, gf[i], "hz"))
    params:set_action(id, function(v) engine[id](v) end)
  end

  params:add_control("gong_decay", "gong decay",
    controlspec.new(0.1, 10, 'exp', 0, 1.5, "s"))
  params:add_control("gong_amp", "gong level",
    controlspec.new(0, 1, 'lin', 0, 0.3))

  params:set_action("gong_decay", function(v) engine.gong_decay(v) end)
  params:set_action("gong_amp", function(v) engine.gong_amp(v) end)

  -- MIDI OUT
  params:add_group("midi_out", "MIDI OUT", 3)
  params:add_number("midi_device", "device", 1, 16, 1)
  params:add_number("midi_channel", "channel", 1, 16, 1)
  params:add_option("midi_active", "midi out", {"off", "on"}, 1)

  params:set_action("midi_device", function(v) midi_out = midi.connect(v) end)

  -- connect midi
  midi_out = midi.connect(params:get("midi_device"))

  -- init scale
  update_scale()

  -- clocks
  clock.run(click_clock)
  clock.run(screen_clock)
  clock.run(sim_clock)

  params:bang()
end

------------------------------------------------------------
-- scale / music mode
------------------------------------------------------------

function update_scale()
  local root = 48 -- C3
  local name = musicutil.SCALES[params:get("scale")].name
  scale_notes = musicutil.generate_scale(root, name, 4)
  note_index = util.clamp(note_index, 1, #scale_notes)
end

function get_music_note()
  -- drunk walk on scale degrees — melodic, not random
  local step = math.random(-2, 2)
  -- bias toward center
  if note_index > #scale_notes * 0.75 then step = step - 1 end
  if note_index < #scale_notes * 0.25 then step = step + 1 end
  note_index = util.clamp(note_index + step, 1, #scale_notes)
  return scale_notes[note_index]
end

------------------------------------------------------------
-- clocks
------------------------------------------------------------

function click_clock()
  while true do
    local div = DIV_VALUES[params:get("click_div")]
    clock.sync(div)

    if params:get("click_sync") == 2 then
      -- chaotic timing jitter (CL philosophy: embrace the wobble)
      local jitter = params:get("chaos") * 0.015
      if jitter > 0.001 then
        clock.sleep(math.random() * jitter)
      end

      -- music mode: pick a scale note
      if params:get("music_mode") == 2 then
        local note = get_music_note()
        local freq = musicutil.note_num_to_freq(note)
        engine.click_pitch(freq)
      end

      -- fire!
      engine.trig(1)
      click_flash = 1
      for i = 1, 4 do
        gong_rings[i] = math.max(gong_rings[i], 0.7 + math.random() * 0.3)
      end

      -- midi
      send_midi_click()
    end
  end
end

function screen_clock()
  while true do
    clock.sleep(1/15)
    redraw()
  end
end

function sim_clock()
  while true do
    clock.sleep(1/30)
    frame = frame + 1

    -- decay visual states
    click_flash = click_flash * 0.82
    chaos_burst = chaos_burst * 0.9
    for i = 1, 4 do
      gong_rings[i] = gong_rings[i] * 0.96
    end

    -- simulate quantussy phases for screen
    for i = 1, 5 do
      local f = params:get("q_freq" .. i)
      q_phase[i] = (q_phase[i] + f * 0.0008) % (math.pi * 2)
      q_wobble[i] = q_wobble[i] + (math.random() - 0.5) * params:get("drift") * 0.3
      q_wobble[i] = q_wobble[i] * 0.94
    end
  end
end

------------------------------------------------------------
-- midi
------------------------------------------------------------

function send_midi_click()
  if params:get("midi_active") ~= 2 or not midi_out then return end
  local ch = params:get("midi_channel")
  local note
  if params:get("music_mode") == 2 then
    note = scale_notes[note_index] or 60
  else
    note = musicutil.freq_to_note_num(params:get("click_pitch"))
  end
  note = util.clamp(math.floor(note), 0, 127)
  local vel = util.clamp(math.floor(80 + params:get("chaos") * 47 * (math.random() - 0.5)), 1, 127)
  midi_out:note_on(note, vel, ch)
  table.insert(held_notes, {note = note, ch = ch})
  -- schedule note off
  clock.run(function()
    clock.sleep(0.05)
    midi_out:note_off(note, 0, ch)
  end)
end

------------------------------------------------------------
-- explorer (autonomous CL self-patch)
------------------------------------------------------------

function toggle_explorer(active)
  explorer_active = active
  if active then
    if explorer_clock_id then clock.cancel(explorer_clock_id) end
    explorer_clock_id = clock.run(explorer_run)
  else
    if explorer_clock_id then
      clock.cancel(explorer_clock_id)
      explorer_clock_id = nil
    end
  end
end

function explorer_run()
  -- like a self-patched CL instrument:
  -- slowly drift parameters, creating emergent behavior
  while explorer_active do
    clock.sleep(0.4 + math.random() * 2.5)
    local choice = math.random(1, 10)

    if choice <= 5 then
      -- drift a quantussy freq (musical: stay near current value)
      local id = "q_freq" .. choice
      local cur = params:get(id)
      local factor = 0.92 + math.random() * 0.16
      params:set(id, util.clamp(cur * factor, 20, 2000))

    elseif choice == 6 then
      local cur = params:get("q_cross")
      params:set("q_cross", util.clamp(cur + (math.random() - 0.5) * 0.08, 0, 1))

    elseif choice == 7 then
      local cur = params:get("q_fold")
      params:set("q_fold", util.clamp(cur + (math.random() - 0.5) * 0.08, 0, 1))

    elseif choice == 8 then
      local cur = params:get("chaos")
      params:set("chaos", util.clamp(cur + (math.random() - 0.5) * 0.06, 0, 1))

    elseif choice == 9 then
      -- shift a gong frequency
      local gi = math.random(1, 4)
      local cur = params:get("gong" .. gi)
      params:set("gong" .. gi, util.clamp(cur * (0.95 + math.random() * 0.1), 50, 5000))

    elseif choice == 10 then
      -- nudge click rate
      local cur = params:get("click_rate")
      params:set("click_rate", util.clamp(cur * (0.9 + math.random() * 0.2), 0.1, 40))
    end
  end
end

------------------------------------------------------------
-- chaos burst
------------------------------------------------------------

function do_chaos_burst()
  chaos_burst = 1
  local prev = params:get("chaos")
  params:set("chaos", math.min(prev + 0.4, 1))
  clock.run(function()
    clock.sleep(0.6)
    params:set("chaos", prev)
  end)
end

------------------------------------------------------------
-- input
------------------------------------------------------------

function enc(n, d)
  if n == 1 then
    page = util.clamp(page + d, 1, 3)

  elseif page == 1 then
    if n == 2 then params:delta("q_cross", d)
    elseif n == 3 then params:delta("q_fold", d) end

  elseif page == 2 then
    if n == 2 then params:delta("click_rate", d)
    elseif n == 3 then params:delta("click_decay", d) end

  elseif page == 3 then
    if n == 2 then params:delta("gong_decay", d)
    elseif n == 3 then params:delta("gong_amp", d) end
  end
end

function key(n, z)
  if n == 2 and z == 1 then
    -- manual click
    if params:get("music_mode") == 2 then
      local note = get_music_note()
      engine.click_pitch(musicutil.note_num_to_freq(note))
    end
    engine.trig(1)
    click_flash = 1
    for i = 1, 4 do
      gong_rings[i] = math.max(gong_rings[i], 0.6 + math.random() * 0.4)
    end
    send_midi_click()

  elseif n == 3 and z == 1 then
    do_chaos_burst()
  end
end

------------------------------------------------------------
-- screen
------------------------------------------------------------

function redraw()
  screen.clear()
  screen.aa(1)
  screen.font_face(1)
  screen.font_size(8)

  -- page tabs
  for i = 1, 3 do
    screen.level(i == page and 15 or 3)
    screen.move(2 + (i - 1) * 44, 7)
    screen.text(PAGES[i])
  end
  screen.level(1)
  screen.move(0, 9)
  screen.line(128, 9)
  screen.stroke()

  -- draw current page
  if page == 1 then draw_quantussy()
  elseif page == 2 then draw_clicker()
  else draw_gongs() end

  -- chaos burst sparks
  if chaos_burst > 0.05 then
    screen.level(math.floor(chaos_burst * 10))
    local n = math.floor(chaos_burst * 15)
    for _ = 1, n do
      screen.pixel(math.random(0, 127), math.random(10, 63))
    end
    screen.fill()
  end

  -- explorer indicator
  if explorer_active then
    screen.level(4 + math.floor(math.sin(frame * 0.15) * 3))
    screen.rect(124, 1, 3, 3)
    screen.fill()
  end

  screen.update()
end

function draw_quantussy()
  local cx, cy = 38, 38
  local r = 17
  local nodes = {}

  -- pentagon node positions with organic wobble
  for i = 1, 5 do
    local angle = (i - 1) * (math.pi * 2 / 5) - math.pi / 2
    local wr = r + math.sin(q_phase[i]) * 2.5 + q_wobble[i] * 4
    nodes[i] = {
      x = cx + math.cos(angle) * wr,
      y = cy + math.sin(angle) * wr
    }
  end

  -- connections (the ring)
  local cross = params:get("q_cross")
  screen.level(math.floor(2 + cross * 8))
  for i = 1, 5 do
    local j = (i % 5) + 1
    local mx = (nodes[i].x + nodes[j].x) / 2
      + math.sin(frame * 0.05 + i) * cross * 3
    local my = (nodes[i].y + nodes[j].y) / 2
      + math.cos(frame * 0.07 + i) * cross * 3
    screen.move(nodes[i].x, nodes[i].y)
    screen.curve(mx, nodes[i].y, mx, nodes[j].y, nodes[j].x, nodes[j].y)
    screen.stroke()
  end

  -- nodes
  for i = 1, 5 do
    local bri = util.clamp(math.floor(6 + math.sin(q_phase[i]) * 5 + click_flash * 4), 1, 15)
    screen.level(bri)
    local nr = 2.5 + math.sin(q_phase[i] * 2) * 1
    screen.circle(nodes[i].x, nodes[i].y, nr)
    screen.fill()
    -- number
    screen.level(0)
    screen.move(nodes[i].x - 2, nodes[i].y + 3)
    screen.font_size(6)
    screen.text(i)
  end

  -- params
  screen.font_size(8)
  local info = {
    {label = "cross", val = string.format("%.2f", params:get("q_cross")), y = 20},
    {label = "fold",  val = string.format("%.2f", params:get("q_fold")),  y = 30},
    {label = "bounds",val = string.format("%.2f", params:get("q_bounds")),y = 40},
    {label = "chaos", val = string.format("%.2f", params:get("chaos")),   y = 50},
  }
  for _, p in ipairs(info) do
    screen.level(8)
    screen.move(72, p.y)
    screen.text(p.label)
    screen.level(15)
    screen.move(106, p.y)
    screen.text(p.val)
  end

  -- fold bar
  screen.level(3)
  screen.rect(72, 56, 52, 3)
  screen.stroke()
  screen.level(12)
  screen.rect(72, 56, math.floor(params:get("q_fold") * 52), 3)
  screen.fill()
end

function draw_clicker()
  local decay = params:get("click_decay")
  local pitch = params:get("click_pitch")
  local ring = params:get("click_ring")

  -- voice 1 waveform
  screen.level(util.clamp(math.floor(4 + click_flash * 11), 1, 15))
  screen.move(4, 28)
  for x = 0, 54 do
    local t = x / 54
    local env = math.exp(-t / (decay * 6))
    local osc = math.sin(t * pitch * 0.015)
    screen.line(4 + x, 26 - env * osc * 10 * (1 + click_flash * 0.5))
  end
  screen.stroke()

  -- voice 2 (golden ratio)
  screen.level(util.clamp(math.floor(3 + click_flash * 8), 1, 15))
  screen.move(4, 42)
  for x = 0, 54 do
    local t = x / 54
    local env = math.exp(-t / (decay * 9))
    local osc = math.sin(t * pitch * 1.618 * 0.015)
    screen.line(4 + x, 40 - env * osc * 8 * (1 + click_flash * 0.5))
  end
  screen.stroke()

  -- ring mod interference
  if ring > 0.05 then
    screen.level(util.clamp(math.floor(ring * 5 + click_flash * 6), 1, 15))
    screen.move(4, 56)
    for x = 0, 54 do
      local t = x / 54
      local env = math.exp(-t / (decay * 7))
      local o1 = math.sin(t * pitch * 0.015)
      local o2 = math.sin(t * pitch * 1.618 * 0.015)
      screen.line(4 + x, 55 - env * o1 * o2 * ring * 7)
    end
    screen.stroke()
  end

  -- labels
  screen.font_size(8)
  local info = {
    {label = "rate",  val = string.format("%.1f", params:get("click_rate")),  y = 18},
    {label = "decay", val = string.format("%.3f", decay),                     y = 28},
    {label = "ring",  val = string.format("%.2f", ring),                      y = 38},
    {label = "pitch", val = string.format("%.0f", pitch),                     y = 48},
  }
  for _, p in ipairs(info) do
    screen.level(8)
    screen.move(66, p.y)
    screen.text(p.label)
    screen.level(15)
    screen.move(96, p.y)
    screen.text(p.val)
  end

  -- sync / music mode
  screen.level(params:get("click_sync") == 2 and 12 or 3)
  screen.move(66, 58)
  screen.text(params:get("click_sync") == 2 and "SYNC" or "FREE")

  if params:get("music_mode") == 2 then
    screen.level(10)
    screen.move(92, 58)
    screen.text("NOTE")
  end
end

function draw_gongs()
  local cx, cy = 30, 38

  -- expanding/decaying rings for each gong
  for i = 1, 4 do
    local rv = gong_rings[i]
    local base_r = 6 + i * 5
    if rv > 0.02 then
      screen.level(util.clamp(math.floor(rv * 13), 1, 15))
      screen.circle(cx, cy, base_r * (1 - rv * 0.15))
      screen.stroke()
      if rv > 0.35 then
        screen.level(util.clamp(math.floor(rv * 6), 1, 15))
        screen.circle(cx, cy, base_r * 0.55)
        screen.stroke()
      end
    else
      screen.level(2)
      screen.circle(cx, cy, base_r)
      screen.stroke()
    end
  end

  -- center exciter
  local cb = util.clamp(math.floor(4 + click_flash * 11), 1, 15)
  screen.level(cb)
  screen.circle(cx, cy, 1.5 + click_flash * 3)
  screen.fill()

  -- labels
  screen.font_size(8)
  for i = 1, 4 do
    local freq = params:get("gong" .. i)
    local bri = util.clamp(math.floor(5 + gong_rings[i] * 8), 1, 15)
    screen.level(bri)
    screen.move(66, 14 + (i - 1) * 11)
    screen.text(i .. ":" .. string.format("%.0f", freq))
  end

  screen.level(8)
  screen.move(66, 56)
  screen.text("decay")
  screen.level(15)
  screen.move(98, 56)
  screen.text(string.format("%.1f", params:get("gong_decay")))
end

------------------------------------------------------------
-- cleanup
------------------------------------------------------------

function cleanup()
  if explorer_clock_id then clock.cancel(explorer_clock_id) end
  if midi_out then
    midi_out:cc(123, 0, params:get("midi_channel"))
  end
end
