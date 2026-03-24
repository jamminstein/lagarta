-- lagarta
-- ciat-lonbarde for norns
--
-- a living instrument
-- the caterpillar plays itself
--
-- E1 page
-- E2/E3 per-page controls
-- K2 manual click / tape rec
-- K3 chaos burst / hold=grid mode
--
-- pages:
--  1 QUANTUSSY  5-osc ring
--  2 CLICKER    impulse + ring mod
--  3 GONGS      resonant bodies
--  4 ROLZ       chaotic rhythms
--  5 TAPE       cocoquantus delay
--  6 LAGARTA    the caterpillar
--
-- grid modes:
--  PATCHBAY  banana jack matrix
--  KEYBOARD  sidrax touch organ
--  GESTURE   record encoder loops
--
-- v2.0 @jamminstein

engine.name = "Lagarta"

local musicutil = require "musicutil"

------------------------------------------------------------
-- constants
------------------------------------------------------------

local PAGES = {"QUANTSSY", "CLICKER", "GONGS", "ROLZ", "TAPE", "LAGARTA"}
local PAGE_FULL = {"QUANTUSSY", "CLICKER", "GONGS", "ROLZ", "TAPE", "LAGARTA"}
local DIV_NAMES = {"1", "1/2", "1/3", "1/4", "1/6", "1/8", "1/12", "1/16"}
local DIV_VALUES = {1, 1/2, 1/3, 1/4, 1/6, 1/8, 1/12, 1/16}
local GRID_MODES = {"PATCHBAY", "KEYBOARD", "GESTURE"}
local PHASE_NAMES = {"DRIFT", "SURGE", "RUPTURE", "DISSOLVE"}
local TAPE_BUF = 16

local MOD_SRC_NAMES = {"q1","q2","q3","q4","q5","clk","gng","cha","r1","r2","r3","r4","tape"}
local MOD_DST_NAMES = {"cross","fold","c.rate","c.pitch","c.dec","g.dec","t.rate","chaos"}
local MOD_DST_PARAMS = {"q_cross","q_fold","click_rate","click_pitch","click_decay","gong_decay","tape_rate","chaos"}

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

-- rolz visual
local rolz_phase = {0, 0, 0, 0}
local rolz_gate = {0, 0, 0, 0}
local rolz_flash = {0, 0, 0, 0}

-- tape
local tape_recording = false
local tape_playing = false
local tape_phase = 0
local tape_reel_angle = 0

-- music mode
local scale_notes = {}
local note_index = 1
local held_notes = {}

-- caterpillar (the living explorer)
local cat_active = false
local cat_clock_id = nil
local cat_phase = 1
local cat_tick = 0
local cat_pl = {8, 6, 4, 8}
local cat_anchors = {}
local cat_x = 64
local cat_y = 38
local cat_dx = 0.3
local cat_dy = 0
local cat_segments = {}
local cat_speed = 0.3
local cat_aggression = 0.5
local NUM_SEGMENTS = 10

-- grid
local g = nil
local grid_mode = 1
local grid_dirty = true
local k3_held = false
local k3_time = 0

-- patchbay
local patch = {}

-- gesture
local gesture_layers = {{}, {}, {}, {}}
local gesture_armed = {false, false, false, false}
local gesture_playing = {false, false, false, false}
local gesture_length = 8

-- midi
local midi_out = nil

------------------------------------------------------------
-- init
------------------------------------------------------------

function init()
  -- init caterpillar segments
  for i = 1, NUM_SEGMENTS do
    cat_segments[i] = {x = 64 - (i-1) * 4, y = 38}
  end

  -- init patchbay
  for s = 1, #MOD_SRC_NAMES do
    patch[s] = {}
    for d = 1, #MOD_DST_NAMES do
      patch[s][d] = 0
    end
  end

  ----------------------------------------
  -- PARAMS
  ----------------------------------------

  params:add_separator("header", "LAGARTA")

  -- GLOBAL
  params:add_group("global", "GLOBAL", 4)
  params:add_control("chaos", "chaos", controlspec.new(0, 1, 'lin', 0, 0.3))
  params:add_control("drift", "drift", controlspec.new(0, 1, 'lin', 0, 0.1))
  params:add_control("amp", "amplitude", controlspec.new(0, 1, 'lin', 0, 0.5))
  params:add_option("grid_mode", "grid mode", GRID_MODES, 1)
  params:set_action("chaos", function(v) engine.chaos(v) end)
  params:set_action("drift", function(v) engine.drift(v) end)
  params:set_action("amp", function(v) engine.amp(v) end)
  params:set_action("grid_mode", function(v) grid_mode = v; grid_dirty = true end)

  -- QUANTUSSY (lower defaults for more bass weight)
  params:add_group("quantussy", "QUANTUSSY", 9)
  local q_freqs = {36, 55, 82, 131, 196}
  for i = 1, 5 do
    local id = "q_freq" .. i
    params:add_control(id, "osc " .. i .. " freq",
      controlspec.new(20, 2000, 'exp', 0, q_freqs[i], "hz"))
    params:set_action(id, function(v) engine[id](v) end)
  end
  params:add_control("q_cross", "cross mod", controlspec.new(0, 1, 'lin', 0, 0.3))
  params:add_control("q_fold", "wavefold", controlspec.new(0, 1, 'lin', 0, 0.5))
  params:add_control("q_bounds", "bounds", controlspec.new(0.05, 1, 'lin', 0, 0.5))
  params:add_control("q_mix", "quantussy mix", controlspec.new(0, 1, 'lin', 0, 0.5))
  params:set_action("q_cross", function(v) engine.q_cross(v) end)
  params:set_action("q_fold", function(v) engine.q_fold(v) end)
  params:set_action("q_bounds", function(v) engine.q_bounds(v) end)
  params:set_action("q_mix", function(v) engine.q_mix(v) end)

  -- SUB + BASS
  params:add_group("sub_bass", "SUB + BASS", 9)
  params:add_control("sub_freq", "sub freq", controlspec.new(15, 200, 'exp', 0, 36, "hz"))
  params:add_control("sub_level", "sub level", controlspec.new(0, 1, 'lin', 0, 0.4))
  params:add_control("sub_width", "sub width", controlspec.new(0.05, 0.95, 'lin', 0, 0.3))
  params:add_control("bass_freq", "bass body freq", controlspec.new(20, 200, 'exp', 0, 55, "hz"))
  params:add_control("bass_decay", "bass body decay", controlspec.new(0.05, 2, 'exp', 0, 0.25, "s"))
  params:add_control("bass_level", "bass body level", controlspec.new(0, 1, 'lin', 0, 0.4))
  params:add_control("bass_click_pitch", "bass click pitch", controlspec.new(20, 400, 'exp', 0, 80, "hz"))
  params:add_control("bass_click_decay", "bass click decay", controlspec.new(0.01, 0.5, 'exp', 0, 0.08, "s"))
  params:add_control("bass_click_amp", "bass click level", controlspec.new(0, 1, 'lin', 0, 0.4))
  params:set_action("sub_freq", function(v) engine.sub_freq(v) end)
  params:set_action("sub_level", function(v) engine.sub_level(v) end)
  params:set_action("sub_width", function(v) engine.sub_width(v) end)
  params:set_action("bass_freq", function(v) engine.bass_freq(v) end)
  params:set_action("bass_decay", function(v) engine.bass_decay(v) end)
  params:set_action("bass_level", function(v) engine.bass_level(v) end)
  params:set_action("bass_click_pitch", function(v) engine.bass_click_pitch(v) end)
  params:set_action("bass_click_decay", function(v) engine.bass_click_decay(v) end)
  params:set_action("bass_click_amp", function(v) engine.bass_click_amp(v) end)

  -- CLICKER
  params:add_group("clicker", "CLICKER", 9)
  params:add_control("click_rate", "rate", controlspec.new(0.1, 40, 'exp', 0, 3, "hz"))
  params:add_control("click_decay", "decay", controlspec.new(0.001, 0.5, 'exp', 0, 0.03, "s"))
  params:add_control("click_pitch", "pitch", controlspec.new(20, 8000, 'exp', 0, 200, "hz"))
  params:add_control("click_ring", "ring mod", controlspec.new(0, 1, 'lin', 0, 0.5))
  params:add_control("click_amp", "click level", controlspec.new(0, 1, 'lin', 0, 0.5))
  params:add_option("click_sync", "sync", {"free", "clock"}, 1)
  params:add_option("click_div", "division", DIV_NAMES, 4)
  params:add_option("music_mode", "music mode", {"off", "on"}, 1)
  params:add_option("scale", "scale", scale_names, 1)
  params:set_action("click_rate", function(v) engine.click_rate(v) end)
  params:set_action("click_decay", function(v) engine.click_decay(v) end)
  params:set_action("click_pitch", function(v) engine.click_pitch(v) end)
  params:set_action("click_ring", function(v) engine.click_ring(v) end)
  params:set_action("click_amp", function(v) engine.click_amp(v) end)
  params:set_action("click_sync", function(v) engine.click_free(v == 1 and 1 or 0) end)
  params:set_action("scale", function() update_scale() end)

  -- GONGS
  params:add_group("gongs", "GONGS", 6)
  local gf = {80, 220, 580, 1200}
  for i = 1, 4 do
    local id = "gong" .. i
    params:add_control(id, "gong " .. i .. " freq",
      controlspec.new(50, 5000, 'exp', 0, gf[i], "hz"))
    params:set_action(id, function(v) engine[id](v) end)
  end
  params:add_control("gong_decay", "gong decay", controlspec.new(0.1, 10, 'exp', 0, 1.5, "s"))
  params:add_control("gong_amp", "gong level", controlspec.new(0, 1, 'lin', 0, 0.3))
  params:set_action("gong_decay", function(v) engine.gong_decay(v) end)
  params:set_action("gong_amp", function(v) engine.gong_amp(v) end)

  -- ROLZ
  params:add_group("rolz", "ROLZ", 6)
  local rr = {1.0, 2.3, 4.7, 0.6}
  for i = 1, 4 do
    local id = "rolz_r" .. i
    params:add_control(id, "rolz " .. i .. " rate",
      controlspec.new(0.01, 20, 'exp', 0, rr[i], "hz"))
    params:set_action(id, function(v) engine[id](v) end)
  end
  params:add_control("rolz_cascade", "cascade", controlspec.new(0, 1, 'lin', 0, 0.5))
  params:add_control("rolz_to_click", "rolz>click", controlspec.new(0, 1, 'lin', 0, 0))
  params:set_action("rolz_cascade", function(v) engine.rolz_cascade(v) end)
  params:set_action("rolz_to_click", function(v) engine.rolz_to_click(v) end)

  -- TAPE
  params:add_group("tape", "TAPE", 5)
  params:add_control("tape_rate", "tape rate", controlspec.new(-4, 4, 'lin', 0, 1))
  params:add_control("tape_level", "tape level", controlspec.new(0, 1, 'lin', 0, 0.5))
  params:add_control("tape_feedback", "feedback", controlspec.new(0, 0.95, 'lin', 0, 0))
  params:add_control("tape_slide", "slide", controlspec.new(0, 1, 'lin', 0, 0))
  params:add_control("tape_gene", "gene size", controlspec.new(0.1, 16, 'exp', 0, 4, "s"))
  params:set_action("tape_rate", function() update_softcut() end)
  params:set_action("tape_level", function() update_softcut() end)
  params:set_action("tape_feedback", function() update_softcut() end)
  params:set_action("tape_slide", function() update_softcut() end)
  params:set_action("tape_gene", function() update_softcut() end)

  -- INPUT
  params:add_group("input", "AUDIO INPUT", 4)
  params:add_control("input_gain", "input gain", controlspec.new(0, 2, 'lin', 0, 0))
  params:add_control("input_fold", "input fold", controlspec.new(0, 1, 'lin', 0, 0))
  params:add_control("input_to_gong", "input>gong", controlspec.new(0, 1, 'lin', 0, 0))
  params:add_control("input_mix", "input mix", controlspec.new(0, 1, 'lin', 0, 0))
  params:set_action("input_gain", function(v) engine.input_gain(v) end)
  params:set_action("input_fold", function(v) engine.input_fold(v) end)
  params:set_action("input_to_gong", function(v) engine.input_to_gong(v) end)
  params:set_action("input_mix", function(v) engine.input_mix(v) end)

  -- WARMTH
  params:add_group("warmth", "WARMTH", 2)
  params:add_control("lpf_freq", "filter freq", controlspec.new(200, 12000, 'exp', 0, 6000, "hz"))
  params:add_control("lpf_res", "filter res", controlspec.new(0.01, 1, 'exp', 0, 0.1))
  params:set_action("lpf_freq", function(v) engine.lpf_freq(v) end)
  params:set_action("lpf_res", function(v) engine.lpf_res(v) end)

  -- CATERPILLAR
  params:add_group("caterpillar", "CATERPILLAR", 6)
  params:add_option("cat_active", "caterpillar", {"off", "on"}, 1)
  params:add_control("cat_aggression", "aggression", controlspec.new(0.1, 1, 'lin', 0, 0.5))
  params:add_number("cat_drift_bars", "drift bars", 2, 16, 8)
  params:add_number("cat_surge_bars", "surge bars", 2, 12, 6)
  params:add_number("cat_rupture_bars", "rupture bars", 2, 8, 4)
  params:add_number("cat_dissolve_bars", "dissolve bars", 2, 16, 8)
  params:set_action("cat_active", function(v) toggle_caterpillar(v == 2) end)
  params:set_action("cat_aggression", function(v) cat_aggression = v end)

  -- MIDI OUT
  params:add_group("midi_out", "MIDI OUT", 3)
  params:add_number("midi_device", "device", 1, 16, 1)
  params:add_number("midi_channel", "channel", 1, 16, 1)
  params:add_option("midi_active", "midi out", {"off", "on"}, 1)
  params:set_action("midi_device", function(v) midi_out = midi.connect(v) end)

  -- GESTURE
  params:add_group("gesture_params", "GESTURE", 1)
  params:add_option("gesture_bars", "loop bars", {"2", "4", "8", "16"}, 3)

  ----------------------------------------
  -- CONNECTIONS
  ----------------------------------------

  midi_out = midi.connect(params:get("midi_device"))
  update_scale()
  init_softcut()

  -- grid
  g = grid.connect()
  g.key = grid_key

  -- clocks
  clock.run(click_clock)
  clock.run(screen_clock)
  clock.run(sim_clock)
  clock.run(grid_redraw_clock)
  clock.run(gesture_clock)

  params:bang()
end

------------------------------------------------------------
-- scale / music mode
------------------------------------------------------------

function update_scale()
  local root = 48
  local name = musicutil.SCALES[params:get("scale")].name
  scale_notes = musicutil.generate_scale(root, name, 4)
  note_index = util.clamp(note_index, 1, #scale_notes)
end

function get_music_note()
  local step = math.random(-2, 2)
  if note_index > #scale_notes * 0.75 then step = step - 1 end
  if note_index < #scale_notes * 0.25 then step = step + 1 end
  note_index = util.clamp(note_index + step, 1, #scale_notes)
  return scale_notes[note_index]
end

------------------------------------------------------------
-- softcut tape (Cocoquantus)
------------------------------------------------------------

function init_softcut()
  softcut.buffer_clear()

  -- voice 1: recorder (captures engine output)
  softcut.enable(1, 1)
  softcut.buffer(1, 1)
  softcut.level(1, 0)
  softcut.rate(1, 1)
  softcut.loop(1, 0)
  softcut.position(1, 0)
  softcut.rec_level(1, 1)
  softcut.pre_level(1, 0)
  softcut.level_input_cut(1, 1, 1)
  softcut.level_input_cut(2, 1, 1)
  softcut.rec(1, 0)
  softcut.play(1, 0)
  softcut.fade_time(1, 0.01)

  -- voice 2: player (loop with pitch shift)
  softcut.enable(2, 1)
  softcut.buffer(2, 1)
  softcut.level(2, 0.5)
  softcut.rate(2, 1)
  softcut.loop(2, 1)
  softcut.loop_start(2, 0)
  softcut.loop_end(2, TAPE_BUF)
  softcut.position(2, 0)
  softcut.rec(2, 0)
  softcut.play(2, 0)
  softcut.fade_time(2, 0.01)
  softcut.rate_slew_time(2, 0.1)
  softcut.level_slew_time(2, 0.05)

  -- route engine output to softcut
  audio.level_eng_cut(1)

  -- phase polling for visualization
  softcut.phase_quant(2, 0.05)
  softcut.event_phase(function(voice, pos)
    if voice == 2 then tape_phase = pos end
  end)
  softcut.poll_start_phase()
end

function tape_start_recording()
  tape_recording = true
  softcut.buffer_clear()
  softcut.position(1, 0)
  softcut.rec(1, 1)
  softcut.play(1, 1)
end

function tape_stop_recording()
  tape_recording = false
  softcut.rec(1, 0)
  softcut.play(1, 0)
  tape_playing = true
  update_softcut()
  softcut.position(2, 0)
  softcut.play(2, 1)
end

function tape_stop()
  tape_recording = false
  tape_playing = false
  softcut.rec(1, 0)
  softcut.play(1, 0)
  softcut.play(2, 0)
end

function update_softcut()
  if not tape_playing then return end
  local gene = params:get("tape_gene")
  local slide = params:get("tape_slide")
  local start = slide * (TAPE_BUF - gene)
  softcut.loop_start(2, math.max(0, start))
  softcut.loop_end(2, math.min(TAPE_BUF, start + gene))
  softcut.rate(2, params:get("tape_rate"))
  softcut.level(2, params:get("tape_level"))
  local fb = params:get("tape_feedback")
  if fb > 0.01 then
    softcut.rec_level(2, 0.5)
    softcut.pre_level(2, fb)
    softcut.rec(2, 1)
  else
    softcut.rec(2, 0)
    softcut.pre_level(2, 0)
  end
end

------------------------------------------------------------
-- clocks
------------------------------------------------------------

function click_clock()
  while true do
    local div = DIV_VALUES[params:get("click_div")]
    clock.sync(div)
    if params:get("click_sync") == 2 then
      local jitter = params:get("chaos") * 0.015
      if jitter > 0.001 then clock.sleep(math.random() * jitter) end
      if params:get("music_mode") == 2 then
        local note = get_music_note()
        local freq = musicutil.note_num_to_freq(note)
        engine.click_pitch(freq)
        -- bass tracks the melody one octave down
        engine.bass_click_pitch(musicutil.note_num_to_freq(math.max(note - 12, 20)))
        -- sub follows root of current note's octave
        engine.sub_freq(musicutil.note_num_to_freq(math.max(note - 24, 15)))
      end
      engine.trig(1)
      click_flash = 1
      for i = 1, 4 do
        gong_rings[i] = math.max(gong_rings[i], 0.7 + math.random() * 0.3)
      end
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

    -- decay visuals
    click_flash = click_flash * 0.82
    chaos_burst = chaos_burst * 0.9
    for i = 1, 4 do
      gong_rings[i] = gong_rings[i] * 0.96
      rolz_flash[i] = rolz_flash[i] * 0.88
    end

    -- quantussy phase sim
    for i = 1, 5 do
      local f = params:get("q_freq" .. i)
      q_phase[i] = (q_phase[i] + f * 0.0008) % (math.pi * 2)
      q_wobble[i] = q_wobble[i] + (math.random() - 0.5) * params:get("drift") * 0.3
      q_wobble[i] = q_wobble[i] * 0.94
    end

    -- rolz phase sim with cascade
    for i = 1, 4 do
      local r = params:get("rolz_r" .. i)
      rolz_phase[i] = (rolz_phase[i] + r * 0.033) % 1
      local prev = rolz_gate[i]
      rolz_gate[i] = rolz_phase[i] < 0.05 and 1 or 0
      if rolz_gate[i] == 1 and prev == 0 then
        rolz_flash[i] = 1
        if i < 4 then
          rolz_phase[i+1] = (rolz_phase[i+1] + params:get("rolz_cascade") * 0.15) % 1
        end
      end
    end

    -- tape reel animation
    if tape_playing or tape_recording then
      tape_reel_angle = (tape_reel_angle + math.abs(params:get("tape_rate")) * 0.1) % (math.pi * 2)
    end

    -- caterpillar movement
    if cat_active then update_caterpillar_visual() end

    -- patchbay modulation routing
    apply_patchbay_modulation()
  end
end

------------------------------------------------------------
-- patchbay modulation routing (30Hz)
------------------------------------------------------------

function apply_patchbay_modulation()
  local src_vals = {
    math.sin(q_phase[1]), math.sin(q_phase[2]), math.sin(q_phase[3]),
    math.sin(q_phase[4]), math.sin(q_phase[5]),
    click_flash,
    math.max(gong_rings[1], gong_rings[2], gong_rings[3], gong_rings[4]),
    params:get("chaos"),
    rolz_gate[1], rolz_gate[2], rolz_gate[3], rolz_gate[4],
    tape_phase / TAPE_BUF
  }

  for d = 1, #MOD_DST_PARAMS do
    local mod_sum = 0
    local has_mod = false
    for s = 1, #MOD_SRC_NAMES do
      if patch[s] and patch[s][d] and patch[s][d] > 0 then
        mod_sum = mod_sum + (src_vals[s] or 0) * (patch[s][d] / 3)
        has_mod = true
      end
    end
    if has_mod and mod_sum ~= 0 then
      local pid = MOD_DST_PARAMS[d]
      local p = params:lookup_param(pid)
      if p and p.controlspec then
        local base = params:get(pid)
        local range = p.controlspec.maxval - p.controlspec.minval
        local modulated = util.clamp(base + mod_sum * range * 0.25,
          p.controlspec.minval, p.controlspec.maxval)
        engine[pid](modulated)
      end
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
  clock.run(function()
    clock.sleep(0.05)
    midi_out:note_off(note, 0, ch)
  end)
end

------------------------------------------------------------
-- caterpillar bandmate (the living explorer)
------------------------------------------------------------

function toggle_caterpillar(active)
  cat_active = active
  if active then
    save_cat_anchors()
    cat_phase = 1
    cat_tick = 0
    cat_pl = {
      params:get("cat_drift_bars"),
      params:get("cat_surge_bars"),
      params:get("cat_rupture_bars"),
      params:get("cat_dissolve_bars")
    }
    if cat_clock_id then clock.cancel(cat_clock_id) end
    cat_clock_id = clock.run(caterpillar_clock)
  else
    if cat_clock_id then
      clock.cancel(cat_clock_id)
      cat_clock_id = nil
    end
  end
end

function save_cat_anchors()
  cat_anchors = {}
  for i = 1, 5 do cat_anchors["q_freq" .. i] = params:get("q_freq" .. i) end
  cat_anchors.q_cross = params:get("q_cross")
  cat_anchors.q_fold = params:get("q_fold")
  cat_anchors.chaos = params:get("chaos")
  cat_anchors.click_rate = params:get("click_rate")
  for i = 1, 4 do cat_anchors["gong" .. i] = params:get("gong" .. i) end
  cat_anchors.gong_decay = params:get("gong_decay")
  for i = 1, 4 do cat_anchors["rolz_r" .. i] = params:get("rolz_r" .. i) end
end

local function nudge(name, amount, lo, hi)
  params:set(name, util.clamp(params:get(name) + amount, lo, hi))
end

local function nudge_mul(name, factor, lo, hi)
  params:set(name, util.clamp(params:get(name) * factor, lo, hi))
end

function caterpillar_clock()
  while cat_active do
    clock.sync(1)
    cat_tick = cat_tick + 1

    local agg = cat_aggression

    -- phase-specific behavior
    if cat_phase == 1 then -- DRIFT: gentle exploration
      if math.random() < 0.3 then
        local i = math.random(1, 5)
        nudge_mul("q_freq" .. i, 0.98 + math.random() * 0.04, 20, 2000)
      end
      if math.random() < 0.1 then nudge("q_cross", (math.random() - 0.5) * 0.02 * agg, 0, 1) end
      if math.random() < 0.1 then nudge("q_fold", (math.random() - 0.5) * 0.02 * agg, 0, 1) end
      cat_speed = 0.2

    elseif cat_phase == 2 then -- SURGE: building
      if math.random() < 0.5 then
        local i = math.random(1, 5)
        nudge_mul("q_freq" .. i, 0.95 + math.random() * 0.1, 20, 2000)
      end
      nudge("q_cross", 0.01 * agg, 0, 1)
      nudge("q_fold", 0.01 * agg, 0, 1)
      if math.random() < 0.3 then nudge("click_rate", 0.2 * agg, 0.1, 40) end
      if math.random() < 0.2 then nudge("rolz_to_click", 0.02 * agg, 0, 1) end
      if math.random() < 0.2 then nudge("rolz_cascade", 0.01 * agg, 0, 1) end
      -- bass surges: increase weight
      if math.random() < 0.2 then nudge("sub_level", 0.02 * agg, 0, 1) end
      if math.random() < 0.2 then nudge("bass_click_amp", 0.02 * agg, 0, 1) end
      if math.random() < 0.15 then nudge_mul("bass_freq", 0.95 + math.random() * 0.1, 20, 200) end
      cat_speed = 0.5

    elseif cat_phase == 3 then -- RUPTURE: maximum chaos
      if math.random() < 0.7 then
        local i = math.random(1, 5)
        nudge_mul("q_freq" .. i, 0.85 + math.random() * 0.3, 20, 2000)
      end
      nudge("q_fold", 0.03 * agg, 0, 1)
      nudge("chaos", 0.02 * agg, 0, 1)
      if math.random() < 0.4 then nudge("click_rate", (math.random() - 0.3) * 2 * agg, 0.1, 40) end
      -- bass goes wild: pitch shifts, level spikes
      if math.random() < 0.3 then nudge_mul("bass_click_pitch", 0.8 + math.random() * 0.4, 20, 400) end
      if math.random() < 0.3 then nudge_mul("sub_freq", 0.85 + math.random() * 0.3, 15, 200) end
      if math.random() < 0.2 then nudge("bass_click_decay", (math.random() - 0.5) * 0.03 * agg, 0.01, 0.5) end
      if math.random() < 0.3 then
        local gi = math.random(1, 4)
        nudge_mul("gong" .. gi, 0.9 + math.random() * 0.2, 50, 5000)
      end
      if math.random() < 0.15 then do_chaos_burst() end
      -- randomly patch/unpatch in patchbay
      if math.random() < 0.1 then
        local s = math.random(1, #MOD_SRC_NAMES)
        local d = math.random(1, #MOD_DST_NAMES)
        patch[s][d] = math.random(0, 2)
        grid_dirty = true
      end
      cat_speed = 1.2

    elseif cat_phase == 4 then -- DISSOLVE: return to calm
      for i = 1, 5 do
        local anchor = cat_anchors["q_freq" .. i] or params:get("q_freq" .. i)
        local cur = params:get("q_freq" .. i)
        params:set("q_freq" .. i, cur + (anchor - cur) * 0.05 * agg)
      end
      nudge("q_cross", -0.01 * agg, 0, 1)
      nudge("q_fold", -0.015 * agg, 0, 1)
      nudge("chaos", -0.01 * agg, 0, 1)
      nudge("click_rate", -0.1 * agg, 0.1, 40)
      nudge("rolz_to_click", -0.02 * agg, 0, 1)
      -- gongs drift back
      for i = 1, 4 do
        local anchor = cat_anchors["gong" .. i] or params:get("gong" .. i)
        local cur = params:get("gong" .. i)
        params:set("gong" .. i, cur + (anchor - cur) * 0.04 * agg)
      end
      cat_speed = 0.15
    end

    -- phase transition
    if cat_tick >= cat_pl[cat_phase] * 4 then
      cat_tick = 0
      cat_phase = (cat_phase % 4) + 1
      cat_pl[cat_phase] = util.clamp(
        params:get("cat_" .. string.lower(PHASE_NAMES[cat_phase]) .. "_bars")
          + math.random(-2, 2), 2, 16)
      if cat_phase == 1 then save_cat_anchors() end
    end
  end
end

function update_caterpillar_visual()
  -- caterpillar movement based on phase
  local wobble = cat_speed * (1 + cat_phase * 0.3)

  -- head direction changes
  cat_dx = cat_dx + (math.random() - 0.5) * wobble * 0.15
  cat_dy = cat_dy + (math.random() - 0.5) * wobble * 0.15
  cat_dx = util.clamp(cat_dx, -1.5, 1.5)
  cat_dy = util.clamp(cat_dy, -0.8, 0.8)

  -- RUPTURE: erratic
  if cat_phase == 3 then
    cat_dx = cat_dx + (math.random() - 0.5) * 0.8
    cat_dy = cat_dy + (math.random() - 0.5) * 0.4
  end
  -- DISSOLVE: curl up
  if cat_phase == 4 then
    cat_dx = cat_dx * 0.95
    cat_dy = cat_dy * 0.95
    -- drift toward center
    cat_dx = cat_dx + (64 - cat_x) * 0.002
    cat_dy = cat_dy + (38 - cat_y) * 0.002
  end

  cat_x = cat_x + cat_dx
  cat_y = cat_y + cat_dy

  -- bounce off edges
  if cat_x < 4 then cat_x = 4; cat_dx = math.abs(cat_dx) end
  if cat_x > 124 then cat_x = 124; cat_dx = -math.abs(cat_dx) end
  if cat_y < 14 then cat_y = 14; cat_dy = math.abs(cat_dy) end
  if cat_y > 60 then cat_y = 60; cat_dy = -math.abs(cat_dy) end

  -- update segments (follow the head)
  cat_segments[1].x = cat_x
  cat_segments[1].y = cat_y
  for i = 2, NUM_SEGMENTS do
    local prev = cat_segments[i-1]
    local seg = cat_segments[i]
    local dx = prev.x - seg.x
    local dy = prev.y - seg.y
    local dist = math.sqrt(dx*dx + dy*dy)
    local spacing = 3.5
    if dist > spacing then
      local ratio = spacing / dist
      seg.x = prev.x - dx * ratio
      seg.y = prev.y - dy * ratio
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
-- gesture recording
------------------------------------------------------------

function record_gesture(param_id, value)
  for i = 1, 4 do
    if gesture_armed[i] then
      local bars = ({2, 4, 8, 16})[params:get("gesture_bars")]
      local beat_pos = clock.get_beats() % (bars * 4)
      if #gesture_layers[i] < 500 then
        table.insert(gesture_layers[i], {time = beat_pos, param_id = param_id, value = value})
      end
    end
  end
end

function gesture_clock()
  while true do
    clock.sync(1/16)
    local bars = ({2, 4, 8, 16})[params:get("gesture_bars")]
    local beat_pos = clock.get_beats() % (bars * 4)
    for layer = 1, 4 do
      if gesture_playing[layer] and #gesture_layers[layer] > 0 then
        for _, ev in ipairs(gesture_layers[layer]) do
          if math.abs(ev.time - beat_pos) < 0.04 then
            params:set(ev.param_id, ev.value)
          end
        end
      end
    end
  end
end

------------------------------------------------------------
-- grid
------------------------------------------------------------

function grid_key(x, y, z)
  if z == 0 then return end

  if grid_mode == 1 then -- PATCHBAY
    if x <= #MOD_SRC_NAMES and y <= #MOD_DST_NAMES then
      patch[x][y] = (patch[x][y] + 1) % 4
      grid_dirty = true
    end

  elseif grid_mode == 2 then -- KEYBOARD
    if x <= 16 and y <= 8 then
      local octave = 7 - y
      local degree = util.clamp(x, 1, #scale_notes)
      local note = (scale_notes[degree] or 60) + octave * 12
      note = util.clamp(note, 20, 120)
      local note_freq = musicutil.note_num_to_freq(note)
      engine.click_pitch(note_freq)
      engine.bass_click_pitch(musicutil.note_num_to_freq(math.max(note - 12, 20)))
      engine.sub_freq(musicutil.note_num_to_freq(math.max(note - 24, 15)))
      engine.trig(1)
      click_flash = 1
      for i = 1, 4 do
        gong_rings[i] = math.max(gong_rings[i], 0.5 + math.random() * 0.5)
      end
      if params:get("midi_active") == 2 and midi_out then
        local vel = util.clamp(math.floor(127 - y * 12), 40, 127)
        midi_out:note_on(note, vel, params:get("midi_channel"))
        clock.run(function()
          clock.sleep(0.1)
          midi_out:note_off(note, 0, params:get("midi_channel"))
        end)
      end
    end

  elseif grid_mode == 3 then -- GESTURE
    if y <= 4 then
      if x == 1 then
        gesture_armed[y] = not gesture_armed[y]
      elseif x == 2 then
        gesture_layers[y] = {}
        gesture_playing[y] = false
        gesture_armed[y] = false
      elseif x == 3 then
        if #gesture_layers[y] > 0 then
          gesture_playing[y] = not gesture_playing[y]
        end
      end
    end
    grid_dirty = true
  end
end

function grid_redraw_clock()
  while true do
    clock.sleep(1/10)
    if g and g.device then
      g:all(0)
      if grid_mode == 1 then draw_grid_patchbay()
      elseif grid_mode == 2 then draw_grid_keyboard()
      else draw_grid_gesture() end
      g:refresh()
    end
  end
end

function draw_grid_patchbay()
  for x = 1, math.min(#MOD_SRC_NAMES, 16) do
    for y = 1, math.min(#MOD_DST_NAMES, 8) do
      local amt = patch[x] and patch[x][y] or 0
      g:led(x, y, amt * 4) -- 0, 4, 8, 12
    end
  end
end

function draw_grid_keyboard()
  for x = 1, 16 do
    for y = 1, 8 do
      local degree = x
      local is_root = (degree == 1)
      local in_scale = (degree <= #scale_notes)
      if is_root then
        g:led(x, y, 12)
      elseif in_scale then
        g:led(x, y, 6)
      else
        g:led(x, y, 1)
      end
    end
  end
end

function draw_grid_gesture()
  for y = 1, 4 do
    -- arm indicator
    g:led(1, y, gesture_armed[y] and 12 or 2)
    -- clear
    g:led(2, y, #gesture_layers[y] > 0 and 6 or 1)
    -- play
    g:led(3, y, gesture_playing[y] and 10 or (#gesture_layers[y] > 0 and 4 or 1))
    -- position dots
    if gesture_playing[y] and #gesture_layers[y] > 0 then
      local bars = ({2, 4, 8, 16})[params:get("gesture_bars")]
      local pos = clock.get_beats() % (bars * 4)
      local col = math.floor(pos / (bars * 4) * 13) + 4
      if col >= 4 and col <= 16 then g:led(col, y, 8) end
    end
  end
end

------------------------------------------------------------
-- input
------------------------------------------------------------

function enc(n, d)
  if n == 1 then
    page = util.clamp(page + d, 1, 6)
  elseif page == 1 then
    if n == 2 then params:delta("q_cross", d)
    elseif n == 3 then params:delta("q_fold", d) end
    record_gesture(n == 2 and "q_cross" or "q_fold", params:get(n == 2 and "q_cross" or "q_fold"))
  elseif page == 2 then
    if n == 2 then params:delta("click_rate", d)
    elseif n == 3 then params:delta("click_decay", d) end
    record_gesture(n == 2 and "click_rate" or "click_decay",
      params:get(n == 2 and "click_rate" or "click_decay"))
  elseif page == 3 then
    if n == 2 then params:delta("gong_decay", d)
    elseif n == 3 then params:delta("gong_amp", d) end
  elseif page == 4 then
    if n == 2 then params:delta("rolz_cascade", d)
    elseif n == 3 then params:delta("rolz_to_click", d) end
  elseif page == 5 then
    if n == 2 then params:delta("tape_rate", d)
    elseif n == 3 then params:delta("tape_slide", d) end
  elseif page == 6 then
    if n == 2 then params:delta("cat_aggression", d)
    elseif n == 3 then
      -- cycle phase bar lengths
      local p = PHASE_NAMES[cat_phase]
      params:delta("cat_" .. string.lower(p) .. "_bars", d)
    end
  end
end

function key(n, z)
  if n == 2 and z == 1 then
    if page == 5 then
      -- tape controls
      if tape_recording then
        tape_stop_recording()
      elseif tape_playing then
        tape_stop()
      else
        tape_start_recording()
      end
    elseif page == 6 then
      -- toggle caterpillar
      params:set("cat_active", cat_active and 1 or 2)
    else
      -- manual click
      if params:get("music_mode") == 2 then
        local note = get_music_note()
        local freq = musicutil.note_num_to_freq(note)
        engine.click_pitch(freq)
        engine.bass_click_pitch(musicutil.note_num_to_freq(math.max(note - 12, 20)))
        engine.sub_freq(musicutil.note_num_to_freq(math.max(note - 24, 15)))
      end
      engine.trig(1)
      click_flash = 1
      for i = 1, 4 do
        gong_rings[i] = math.max(gong_rings[i], 0.6 + math.random() * 0.4)
      end
      send_midi_click()
    end
  elseif n == 3 then
    if z == 1 then
      k3_held = true
      k3_time = util.time()
    else
      k3_held = false
      if util.time() - k3_time > 0.5 then
        -- long press: cycle grid mode
        params:set("grid_mode", (grid_mode % 3) + 1)
      else
        -- short press: chaos burst
        do_chaos_burst()
      end
    end
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

  -- page tabs (6 compact tabs)
  for i = 1, 6 do
    screen.level(i == page and 15 or 3)
    screen.move(1 + (i-1) * 21, 7)
    screen.text(PAGES[i])
  end
  screen.level(1)
  screen.move(0, 9)
  screen.line(128, 9)
  screen.stroke()

  if page == 1 then draw_quantussy()
  elseif page == 2 then draw_clicker()
  elseif page == 3 then draw_gongs()
  elseif page == 4 then draw_rolz()
  elseif page == 5 then draw_tape()
  elseif page == 6 then draw_caterpillar() end

  -- chaos burst sparks
  if chaos_burst > 0.05 then
    screen.level(math.floor(chaos_burst * 10))
    for _ = 1, math.floor(chaos_burst * 15) do
      screen.pixel(math.random(0, 127), math.random(10, 63))
    end
    screen.fill()
  end

  -- caterpillar active indicator (small worm on all pages)
  if cat_active and page ~= 6 then
    screen.level(4 + math.floor(math.sin(frame * 0.15) * 3))
    local ix = 122 + math.sin(frame * 0.1) * 2
    screen.circle(ix, 4, 1.5)
    screen.fill()
    screen.circle(ix + 3, 4 + math.sin(frame * 0.2), 1)
    screen.fill()
  end

  -- grid mode indicator
  if g and g.device then
    screen.level(2)
    screen.move(0, 63)
    screen.font_size(6)
    screen.text(GRID_MODES[grid_mode])
  end

  screen.update()
end

------------------------------------------------------------
-- page 1: QUANTUSSY
------------------------------------------------------------

function draw_quantussy()
  local cx, cy = 38, 38
  local r = 17
  local nodes = {}

  for i = 1, 5 do
    local angle = (i - 1) * (math.pi * 2 / 5) - math.pi / 2
    local wr = r + math.sin(q_phase[i]) * 2.5 + q_wobble[i] * 4
    nodes[i] = {
      x = cx + math.cos(angle) * wr,
      y = cy + math.sin(angle) * wr
    }
  end

  local cross = params:get("q_cross")
  screen.level(math.floor(2 + cross * 8))
  for i = 1, 5 do
    local j = (i % 5) + 1
    local mx = (nodes[i].x + nodes[j].x) / 2 + math.sin(frame * 0.05 + i) * cross * 3
    local my = (nodes[i].y + nodes[j].y) / 2 + math.cos(frame * 0.07 + i) * cross * 3
    screen.move(nodes[i].x, nodes[i].y)
    screen.curve(mx, nodes[i].y, mx, nodes[j].y, nodes[j].x, nodes[j].y)
    screen.stroke()
  end

  for i = 1, 5 do
    local bri = util.clamp(math.floor(6 + math.sin(q_phase[i]) * 5 + click_flash * 4), 1, 15)
    screen.level(bri)
    screen.circle(nodes[i].x, nodes[i].y, 2.5 + math.sin(q_phase[i] * 2))
    screen.fill()
    screen.level(0)
    screen.move(nodes[i].x - 2, nodes[i].y + 3)
    screen.font_size(6)
    screen.text(i)
  end

  screen.font_size(8)
  local info = {
    {l="cross", v=string.format("%.2f", params:get("q_cross")), y=20},
    {l="fold",  v=string.format("%.2f", params:get("q_fold")),  y=30},
    {l="bounds",v=string.format("%.2f", params:get("q_bounds")),y=40},
    {l="chaos", v=string.format("%.2f", params:get("chaos")),   y=50},
  }
  for _, p in ipairs(info) do
    screen.level(8); screen.move(72, p.y); screen.text(p.l)
    screen.level(15); screen.move(106, p.y); screen.text(p.v)
  end
  screen.level(3); screen.rect(72, 56, 52, 3); screen.stroke()
  screen.level(12); screen.rect(72, 56, math.floor(params:get("q_fold") * 52), 3); screen.fill()
end

------------------------------------------------------------
-- page 2: CLICKER
------------------------------------------------------------

function draw_clicker()
  local decay = params:get("click_decay")
  local pitch = params:get("click_pitch")
  local ring = params:get("click_ring")

  screen.level(util.clamp(math.floor(4 + click_flash * 11), 1, 15))
  screen.move(4, 28)
  for x = 0, 54 do
    local t = x / 54
    local env = math.exp(-t / (decay * 6))
    screen.line(4 + x, 26 - env * math.sin(t * pitch * 0.015) * 10 * (1 + click_flash * 0.5))
  end
  screen.stroke()

  screen.level(util.clamp(math.floor(3 + click_flash * 8), 1, 15))
  screen.move(4, 42)
  for x = 0, 54 do
    local t = x / 54
    local env = math.exp(-t / (decay * 9))
    screen.line(4 + x, 40 - env * math.sin(t * pitch * 1.618 * 0.015) * 8 * (1 + click_flash * 0.5))
  end
  screen.stroke()

  if ring > 0.05 then
    screen.level(util.clamp(math.floor(ring * 5 + click_flash * 6), 1, 15))
    screen.move(4, 56)
    for x = 0, 54 do
      local t = x / 54
      local env = math.exp(-t / (decay * 7))
      screen.line(4 + x, 55 - env * math.sin(t * pitch * 0.015) * math.sin(t * pitch * 1.618 * 0.015) * ring * 7)
    end
    screen.stroke()
  end

  screen.font_size(8)
  local info = {
    {l="rate",  v=string.format("%.1f", params:get("click_rate")),  y=18},
    {l="decay", v=string.format("%.3f", decay),                     y=28},
    {l="ring",  v=string.format("%.2f", ring),                      y=38},
    {l="pitch", v=string.format("%.0f", pitch),                     y=48},
  }
  for _, p in ipairs(info) do
    screen.level(8); screen.move(66, p.y); screen.text(p.l)
    screen.level(15); screen.move(96, p.y); screen.text(p.v)
  end
  screen.level(params:get("click_sync") == 2 and 12 or 3)
  screen.move(66, 58); screen.text(params:get("click_sync") == 2 and "SYNC" or "FREE")
  if params:get("music_mode") == 2 then
    screen.level(10); screen.move(92, 58); screen.text("NOTE")
  end
end

------------------------------------------------------------
-- page 3: GONGS
------------------------------------------------------------

function draw_gongs()
  local cx, cy = 30, 38
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
      screen.level(2); screen.circle(cx, cy, base_r); screen.stroke()
    end
  end
  screen.level(util.clamp(math.floor(4 + click_flash * 11), 1, 15))
  screen.circle(cx, cy, 1.5 + click_flash * 3); screen.fill()

  screen.font_size(8)
  for i = 1, 4 do
    screen.level(util.clamp(math.floor(5 + gong_rings[i] * 8), 1, 15))
    screen.move(66, 14 + (i-1) * 11)
    screen.text(i .. ":" .. string.format("%.0f", params:get("gong" .. i)))
  end
  screen.level(8); screen.move(66, 56); screen.text("decay")
  screen.level(15); screen.move(98, 56); screen.text(string.format("%.1f", params:get("gong_decay")))
end

------------------------------------------------------------
-- page 4: ROLZ
------------------------------------------------------------

function draw_rolz()
  for i = 1, 4 do
    local lane_y = 12 + (i-1) * 13
    local bri = util.clamp(math.floor(3 + rolz_flash[i] * 12), 1, 15)

    -- sawtooth waveform
    screen.level(bri)
    screen.move(2, lane_y + 10)
    for x = 0, 55 do
      local phase = (rolz_phase[i] + x * 0.03) % 1
      local y_val = lane_y + 10 - phase * 8
      screen.line(2 + x, y_val)
    end
    screen.stroke()

    -- gate flash bar
    if rolz_flash[i] > 0.1 then
      screen.level(util.clamp(math.floor(rolz_flash[i] * 15), 1, 15))
      screen.rect(0, lane_y, 2, 11)
      screen.fill()
    end

    -- cascade arrow
    if i < 4 then
      local cascade = params:get("rolz_cascade")
      screen.level(math.floor(2 + cascade * 8))
      screen.move(58, lane_y + 8)
      screen.line(58, lane_y + 14)
      screen.stroke()
      screen.move(56, lane_y + 12); screen.line(58, lane_y + 14); screen.line(60, lane_y + 12)
      screen.stroke()
    end
  end

  screen.font_size(8)
  screen.level(8); screen.move(66, 20); screen.text("cascade")
  screen.level(15); screen.move(106, 20); screen.text(string.format("%.2f", params:get("rolz_cascade")))
  screen.level(8); screen.move(66, 32); screen.text("to clk")
  screen.level(15); screen.move(106, 32); screen.text(string.format("%.2f", params:get("rolz_to_click")))

  for i = 1, 4 do
    screen.level(6)
    screen.move(66, 40 + (i-1) * 7)
    screen.text("r" .. i .. ":" .. string.format("%.1f", params:get("rolz_r" .. i)))
  end
end

------------------------------------------------------------
-- page 5: TAPE
------------------------------------------------------------

function draw_tape()
  -- dual reels
  local lx, rx = 25, 50
  local ry = 34
  local reel_r = 8

  for _, cx in ipairs({lx, rx}) do
    screen.level(tape_recording and 10 or (tape_playing and 8 or 3))
    screen.circle(cx, ry, reel_r)
    screen.stroke()
    -- spokes
    for s = 0, 2 do
      local a = tape_reel_angle + s * math.pi * 2 / 3
      screen.move(cx, ry)
      screen.line(cx + math.cos(a) * reel_r, ry + math.sin(a) * reel_r)
      screen.stroke()
    end
  end

  -- tape path
  screen.level(6)
  screen.move(lx + reel_r, ry - 2)
  screen.line(rx - reel_r, ry - 2)
  screen.stroke()

  -- playhead position
  if tape_playing then
    local gene = params:get("tape_gene")
    local slide = params:get("tape_slide")
    local pos_x = lx + reel_r + (tape_phase / TAPE_BUF) * (rx - lx - reel_r * 2)
    screen.level(15)
    screen.move(pos_x, ry - 6)
    screen.line(pos_x, ry + 2)
    screen.stroke()
  end

  -- status
  screen.font_size(8)
  screen.level(15)
  screen.move(20, 52)
  if tape_recording then screen.text("REC")
  elseif tape_playing then screen.text("PLAY")
  else screen.text("STOP") end

  -- params
  screen.level(8); screen.move(66, 18); screen.text("rate")
  screen.level(15); screen.move(100, 18); screen.text(string.format("%.2f", params:get("tape_rate")))
  screen.level(8); screen.move(66, 28); screen.text("slide")
  screen.level(15); screen.move(100, 28); screen.text(string.format("%.2f", params:get("tape_slide")))
  screen.level(8); screen.move(66, 38); screen.text("fdbk")
  screen.level(15); screen.move(100, 38); screen.text(string.format("%.2f", params:get("tape_feedback")))
  screen.level(8); screen.move(66, 48); screen.text("gene")
  screen.level(15); screen.move(100, 48); screen.text(string.format("%.1f", params:get("tape_gene")))
  screen.level(8); screen.move(66, 58); screen.text("level")
  screen.level(15); screen.move(100, 58); screen.text(string.format("%.2f", params:get("tape_level")))
end

------------------------------------------------------------
-- page 6: LAGARTA (the caterpillar)
------------------------------------------------------------

function draw_caterpillar()
  if not cat_active then
    -- sleeping caterpillar
    screen.level(4)
    screen.font_size(8)
    screen.move(30, 35)
    screen.text("K2 to wake the")
    screen.move(30, 46)
    screen.text("caterpillar")
    -- small sleeping worm
    for i = 1, 6 do
      local bri = math.floor(2 + math.sin(frame * 0.05 + i * 0.5) * 1.5)
      screen.level(util.clamp(bri, 1, 4))
      screen.circle(50 + i * 4, 55 + math.sin(frame * 0.03 + i * 0.3) * 1, 2)
      screen.fill()
    end
    return
  end

  -- draw body segments
  for i = NUM_SEGMENTS, 1, -1 do
    local seg = cat_segments[i]
    -- each segment brightness based on which param it represents
    local param_intensity = 0
    if i <= 5 then
      param_intensity = math.abs(math.sin(q_phase[i])) -- quantussy oscs
    elseif i == 6 then
      param_intensity = click_flash
    elseif i == 7 then
      param_intensity = math.max(gong_rings[1], gong_rings[2])
    elseif i == 8 then
      param_intensity = params:get("chaos")
    elseif i <= 10 then
      param_intensity = rolz_flash[i - 8] or 0
    end

    local base_bri = cat_phase == 3 and 8 or (cat_phase == 4 and 3 or 5)
    local bri = util.clamp(math.floor(base_bri + param_intensity * 7
      + math.sin(frame * 0.1 + i * 0.5) * 2), 1, 15)
    screen.level(bri)

    -- segment size: head is bigger
    local r = i == 1 and 3.5 or (2.5 - i * 0.08)
    -- body undulation
    local uy = seg.y + math.sin(frame * 0.08 + i * 0.4) * (cat_speed * 1.5)
    screen.circle(seg.x, uy, r)
    screen.fill()
  end

  -- head details: antennae
  local head = cat_segments[1]
  local ant_len = 5 + math.sin(frame * 0.12) * 2
  screen.level(cat_phase == 3 and 12 or 7)
  -- left antenna
  screen.move(head.x, head.y - 3)
  screen.line(head.x - ant_len * 0.7 + math.sin(frame * 0.15) * 2,
              head.y - 3 - ant_len + math.cos(frame * 0.18) * 1.5)
  screen.stroke()
  -- right antenna
  screen.move(head.x, head.y - 3)
  screen.line(head.x + ant_len * 0.7 + math.cos(frame * 0.13) * 2,
              head.y - 3 - ant_len + math.sin(frame * 0.16) * 1.5)
  screen.stroke()
  -- antenna tips
  screen.circle(head.x - ant_len * 0.7 + math.sin(frame * 0.15) * 2,
                head.y - 3 - ant_len + math.cos(frame * 0.18) * 1.5, 1)
  screen.fill()
  screen.circle(head.x + ant_len * 0.7 + math.cos(frame * 0.13) * 2,
                head.y - 3 - ant_len + math.sin(frame * 0.16) * 1.5, 1)
  screen.fill()

  -- eyes
  screen.level(15)
  screen.circle(head.x - 1.5, head.y - 1, 0.8)
  screen.fill()
  screen.circle(head.x + 1.5, head.y - 1, 0.8)
  screen.fill()

  -- phase name and progress
  screen.level(15)
  screen.font_size(8)
  screen.move(2, 62)
  screen.text(PHASE_NAMES[cat_phase])

  -- progress bar
  local progress = cat_tick / (cat_pl[cat_phase] * 4)
  screen.level(4)
  screen.rect(42, 58, 40, 4)
  screen.stroke()
  screen.level(cat_phase == 3 and 15 or 10)
  screen.rect(42, 58, math.floor(progress * 40), 4)
  screen.fill()

  -- aggression
  screen.level(6)
  screen.move(88, 62)
  screen.text(string.format("%.1f", cat_aggression))

  -- RUPTURE particles
  if cat_phase == 3 then
    screen.level(math.floor(6 + math.random() * 6))
    for _ = 1, 4 do
      screen.pixel(head.x + math.random(-8, 8), head.y + math.random(-8, 8))
    end
    screen.fill()
  end
end

------------------------------------------------------------
-- cleanup
------------------------------------------------------------

function cleanup()
  if cat_clock_id then clock.cancel(cat_clock_id) end
  softcut.rec(1, 0)
  softcut.play(1, 0)
  softcut.play(2, 0)
  softcut.poll_stop_phase()
  if midi_out then
    midi_out:cc(123, 0, params:get("midi_channel"))
  end
  if g and g.device then g:all(0); g:refresh() end
end
