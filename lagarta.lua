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
local MOD_DST_NAMES = {"cross","fold","c.rate","c.pitch","c.dec","g.dec","drift","chaos"}
local MOD_DST_PARAMS = {"q_cross","q_fold","click_rate","click_pitch","click_decay","gong_decay","drift","chaos"}

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

-- musical constants
local INTERVALS = {
  unison = 1, octave = 2, fifth = 1.5, fourth = 4/3,
  maj3 = 5/4, min3 = 6/5, min7 = 9/5, tritone = 1.414
}
local CONSONANT = {1, 2, 1.5, 4/3, 5/4, 3/2}
local DISSONANT = {1.414, 1.067, 1.122, 1.782, 2.378}
local POLY_RATIOS = {3/2, 4/3, 5/4, 5/3, 7/4, 2/3, 3/4}

-- caterpillar species definitions
local SPECIES = {
  verde = {
    name = "VERDE",
    desc = "melodic friend",
    intervals = CONSONANT,
    seg_count = 8,
    speed = 0.25,
    bright_base = 6,
    prefer_scales = {"Major", "Dorian", "Pentatonic Major"},
    click_decay_range = {0.04, 0.15},
    fold_range = {0.1, 0.4},
    chaos_range = {0.05, 0.25},
    gong_decay_range = {2.0, 6.0},
    sub_love = 0.3,
    rhythm_style = "steady",
  },
  venenosa = {
    name = "VENENOSA",
    desc = "venomous chaos",
    intervals = DISSONANT,
    seg_count = 10,
    speed = 0.8,
    bright_base = 9,
    prefer_scales = {"Chromatic", "Whole Tone", "Hungarian Minor"},
    click_decay_range = {0.002, 0.04},
    fold_range = {0.5, 1.0},
    chaos_range = {0.3, 0.8},
    gong_decay_range = {0.3, 1.2},
    sub_love = 0.1,
    rhythm_style = "erratic",
  },
  seda = {
    name = "SEDA",
    desc = "silk ambient",
    intervals = {1, 2, 1.5, 4/3},
    seg_count = 12,
    speed = 0.1,
    bright_base = 3,
    prefer_scales = {"Pentatonic Minor", "Mixolydian", "Dorian"},
    click_decay_range = {0.1, 0.5},
    fold_range = {0.05, 0.2},
    chaos_range = {0.02, 0.12},
    gong_decay_range = {4.0, 10.0},
    sub_love = 0.6,
    rhythm_style = "sparse",
  },
  fogo = {
    name = "FOGO",
    desc = "fire rhythm",
    intervals = {1, 1.5, 2, 4/3, 5/4},
    seg_count = 7,
    speed = 1.0,
    bright_base = 10,
    prefer_scales = {"Minor Pentatonic", "Blues", "Phrygian"},
    click_decay_range = {0.01, 0.06},
    fold_range = {0.3, 0.7},
    chaos_range = {0.15, 0.45},
    gong_decay_range = {0.5, 2.0},
    sub_love = 0.5,
    rhythm_style = "polyrhythm",
  },
}
local SPECIES_ORDER = {"verde", "venenosa", "seda", "fogo"}

-- caterpillar instances (up to 4 active)
local lagartas = {}
local active_species = {}
local cat_selected = 1

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
  params:add_control("q_mix", "quantussy mix", controlspec.new(0, 1, 'lin', 0, 0.25))
  params:set_action("q_cross", function(v) engine.q_cross(v) end)
  params:set_action("q_fold", function(v) engine.q_fold(v) end)
  params:set_action("q_bounds", function(v) engine.q_bounds(v) end)
  params:set_action("q_mix", function(v) engine.q_mix(v) end)

  -- SUB + BASS
  params:add_group("sub_bass", "SUB + BASS", 9)
  params:add_control("sub_freq", "sub freq", controlspec.new(15, 200, 'exp', 0, 36, "hz"))
  params:add_control("sub_level", "sub level", controlspec.new(0, 1, 'lin', 0, 0.15))
  params:add_control("sub_width", "sub width", controlspec.new(0.05, 0.95, 'lin', 0, 0.3))
  params:add_control("bass_freq", "bass body freq", controlspec.new(20, 200, 'exp', 0, 55, "hz"))
  params:add_control("bass_decay", "bass body decay", controlspec.new(0.05, 2, 'exp', 0, 0.25, "s"))
  params:add_control("bass_level", "bass body level", controlspec.new(0, 1, 'lin', 0, 0.2))
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
  params:add_control("click_rate", "rate", controlspec.new(0.1, 40, 'exp', 0, 4, "hz"))
  params:add_control("click_decay", "decay", controlspec.new(0.001, 0.5, 'exp', 0, 0.06, "s"))
  params:add_control("click_pitch", "pitch", controlspec.new(20, 8000, 'exp', 0, 300, "hz"))
  params:add_control("click_ring", "ring mod", controlspec.new(0, 1, 'lin', 0, 0.4))
  params:add_control("click_amp", "click level", controlspec.new(0, 1, 'lin', 0, 0.7))
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
  params:add_control("gong_decay", "gong decay", controlspec.new(0.1, 10, 'exp', 0, 2.0, "s"))
  params:add_control("gong_amp", "gong level", controlspec.new(0, 1, 'lin', 0, 0.5))
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
  params:add_control("rolz_to_click", "rolz>click", controlspec.new(0, 1, 'lin', 0, 0.3))
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
  params:add_control("lpf_freq", "filter freq", controlspec.new(200, 12000, 'exp', 0, 3500, "hz"))
  params:add_control("lpf_res", "filter res", controlspec.new(0.01, 1, 'exp', 0, 0.1))
  params:set_action("lpf_freq", function(v) engine.lpf_freq(v) end)
  params:set_action("lpf_res", function(v) engine.lpf_res(v) end)

  -- LAGARTAS (caterpillar bandmates)
  params:add_group("lagartas", "LAGARTAS", 5)
  params:add_option("cat_verde", "verde (melodic)", {"off", "on"}, 1)
  params:add_option("cat_venenosa", "venenosa (chaos)", {"off", "on"}, 1)
  params:add_option("cat_seda", "seda (ambient)", {"off", "on"}, 1)
  params:add_option("cat_fogo", "fogo (rhythm)", {"off", "on"}, 1)
  params:add_control("cat_aggression", "aggression", controlspec.new(0.1, 1, 'lin', 0, 0.5))
  for _, sp in ipairs(SPECIES_ORDER) do
    params:set_action("cat_" .. sp, function(v)
      toggle_lagarta(sp, v == 2)
    end)
  end

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
  clock.run(screen_clock)
  clock.run(sim_clock)
  clock.run(grid_redraw_clock)
  clock.run(safe_click_clock)
  clock.run(safe_gesture_clock)

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

function safe_click_clock()
  clock.sleep(1)
  while true do
    local div = DIV_VALUES[params:get("click_div")]
    clock.sleep(div * math.max(clock.get_beat_sec(), 0.05))
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

    -- update all lagarta visuals
    update_all_lagartas()

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
        pcall(function() engine[pid](modulated) end)
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
-- lagarta bandmates (multi-personality musical system)
------------------------------------------------------------

local function nudge(name, amount, lo, hi)
  pcall(function()
    params:set(name, util.clamp(params:get(name) + amount, lo, hi))
  end)
end

local function set_safe(name, val)
  pcall(function() params:set(name, val) end)
end

local function harmonic_freq(root_freq, intervals)
  local ratio = intervals[math.random(1, #intervals)]
  return root_freq * ratio
end

local function snap_freq_to_scale(freq)
  -- find the nearest scale note frequency
  if #scale_notes == 0 then return freq end
  local best_freq = freq
  local best_dist = math.huge
  for _, note in ipairs(scale_notes) do
    local nf = musicutil.note_num_to_freq(note)
    -- check multiple octaves
    for oct = -2, 3 do
      local test = nf * (2 ^ oct)
      local dist = math.abs(math.log(freq / test))
      if dist < best_dist then
        best_dist = dist
        best_freq = test
      end
    end
  end
  return best_freq
end

function create_lagarta(species_key)
  local sp = SPECIES[species_key]
  if not sp then return nil end
  local L = {
    species = species_key,
    spec = sp,
    active = true,
    tick = 0,
    -- visual state
    x = math.random(10, 118),
    y = math.random(18, 55),
    dx = (math.random() - 0.5) * 0.5,
    dy = (math.random() - 0.5) * 0.3,
    segments = {},
    particles = {},
    -- memory system
    memory = {},
    best_memory = nil,
    -- clock
    clock_id = nil,
  }
  -- init segments
  for i = 1, sp.seg_count do
    L.segments[i] = {x = L.x - (i - 1) * 3, y = L.y}
  end
  return L
end

function toggle_lagarta(species_key, on)
  if on then
    if lagartas[species_key] then return end -- already active
    local L = create_lagarta(species_key)
    if not L then return end
    lagartas[species_key] = L
    -- start thinking clock
    L.clock_id = clock.run(function()
      lagarta_think(species_key)
    end)
  else
    local L = lagartas[species_key]
    if L then
      L.active = false
      if L.clock_id then
        pcall(function() clock.cancel(L.clock_id) end)
        L.clock_id = nil
      end
      lagartas[species_key] = nil
    end
  end
end

function lagarta_think(species_key)
  local L = lagartas[species_key]
  if not L then return end
  local sp = L.spec
  local agg_base = 0.5

  while L.active and lagartas[species_key] do
    pcall(function() agg_base = params:get("cat_aggression") end)
    local agg = agg_base
    L.tick = L.tick + 1

    --------------------------------------------
    -- VERDE: melodic friend
    --------------------------------------------
    if species_key == "verde" then
      -- tune quantussy oscillators to consonant intervals from root
      if math.random() < 0.25 * agg then
        local root = 36
        pcall(function() root = params:get("q_freq1") end)
        local i = math.random(1, 5)
        local target = snap_freq_to_scale(harmonic_freq(root, sp.intervals))
        target = util.clamp(target, 20, 2000)
        -- gentle drift toward target
        pcall(function()
          local cur = params:get("q_freq" .. i)
          set_safe("q_freq" .. i, cur + (target - cur) * 0.15 * agg)
        end)
      end
      -- prefer long click decays (melodic)
      if math.random() < 0.15 * agg then
        local dec = sp.click_decay_range[1] + math.random() * (sp.click_decay_range[2] - sp.click_decay_range[1])
        set_safe("click_decay", dec)
      end
      -- keep fold and chaos low
      if math.random() < 0.1 then
        local fold_target = sp.fold_range[1] + math.random() * (sp.fold_range[2] - sp.fold_range[1])
        nudge("q_fold", (fold_target - (params:get("q_fold") or 0.3)) * 0.1 * agg, 0, 1)
      end
      if math.random() < 0.1 then
        local chaos_target = sp.chaos_range[1] + math.random() * (sp.chaos_range[2] - sp.chaos_range[1])
        nudge("chaos", (chaos_target - (params:get("chaos") or 0.3)) * 0.08 * agg, 0, 1)
      end
      -- bass tracks scale notes at lower octaves
      if math.random() < 0.2 * agg and #scale_notes > 0 then
        local note = scale_notes[math.random(1, math.min(5, #scale_notes))]
        local bass_freq = musicutil.note_num_to_freq(math.max(note - 12, 20))
        set_safe("bass_freq", util.clamp(bass_freq, 20, 200))
        set_safe("sub_freq", util.clamp(musicutil.note_num_to_freq(math.max(note - 24, 15)), 15, 200))
      end
      -- boost sub gently
      if math.random() < 0.1 then
        nudge("sub_level", sp.sub_love * 0.02 * agg, 0, 1)
      end
      -- gongs tuned to harmonics
      if math.random() < 0.12 * agg then
        local gi = math.random(1, 4)
        local root = 80
        pcall(function() root = params:get("gong1") end)
        local target = harmonic_freq(root, sp.intervals)
        target = util.clamp(target, 50, 5000)
        pcall(function()
          local cur = params:get("gong" .. gi)
          set_safe("gong" .. gi, cur + (target - cur) * 0.12 * agg)
        end)
      end
      -- gong decay in species range
      if math.random() < 0.08 then
        local dec = sp.gong_decay_range[1] + math.random() * (sp.gong_decay_range[2] - sp.gong_decay_range[1])
        set_safe("gong_decay", dec)
      end

    --------------------------------------------
    -- VENENOSA: venomous chaos
    --------------------------------------------
    elseif species_key == "venenosa" then
      -- detune to dissonant intervals
      if math.random() < 0.4 * agg then
        local i = math.random(1, 5)
        local root = 100 + math.random() * 400
        pcall(function() root = params:get("q_freq1") end)
        local target = harmonic_freq(root, sp.intervals)
        target = util.clamp(target, 20, 2000)
        set_safe("q_freq" .. i, target)
      end
      -- push fold and chaos high
      if math.random() < 0.3 * agg then
        local fold_target = sp.fold_range[1] + math.random() * (sp.fold_range[2] - sp.fold_range[1])
        nudge("q_fold", (fold_target - (params:get("q_fold") or 0.5)) * 0.2 * agg, 0, 1)
      end
      if math.random() < 0.25 * agg then
        local chaos_target = sp.chaos_range[1] + math.random() * (sp.chaos_range[2] - sp.chaos_range[1])
        nudge("chaos", (chaos_target - (params:get("chaos") or 0.3)) * 0.15 * agg, 0, 1)
      end
      -- short harsh clicks
      if math.random() < 0.2 * agg then
        local dec = sp.click_decay_range[1] + math.random() * (sp.click_decay_range[2] - sp.click_decay_range[1])
        set_safe("click_decay", dec)
      end
      -- erratic rate changes
      if math.random() < 0.25 * agg then
        nudge("click_rate", (math.random() - 0.3) * 4 * agg, 0.1, 40)
      end
      -- occasional chaos bursts
      if math.random() < 0.06 * agg then
        do_chaos_burst()
      end
      -- mess with patchbay connections
      if math.random() < 0.08 * agg then
        local s = math.random(1, #MOD_SRC_NAMES)
        local d = math.random(1, #MOD_DST_NAMES)
        patch[s][d] = math.random(0, 3)
        grid_dirty = true
      end
      -- dissonant gong tuning
      if math.random() < 0.15 * agg then
        local gi = math.random(1, 4)
        local root = 200 + math.random() * 800
        local target = harmonic_freq(root, sp.intervals)
        set_safe("gong" .. gi, util.clamp(target, 50, 5000))
      end
      -- short gong decay
      if math.random() < 0.1 then
        local dec = sp.gong_decay_range[1] + math.random() * (sp.gong_decay_range[2] - sp.gong_decay_range[1])
        set_safe("gong_decay", dec)
      end
      -- bass: harsh pitch shifts
      if math.random() < 0.15 * agg then
        set_safe("bass_click_pitch", 20 + math.random() * 380)
      end

    --------------------------------------------
    -- SEDA: silk ambient
    --------------------------------------------
    elseif species_key == "seda" then
      -- very slow drift toward consonance
      if math.random() < 0.12 * agg then
        local i = math.random(1, 5)
        local root = 36
        pcall(function() root = params:get("q_freq1") end)
        local target = snap_freq_to_scale(harmonic_freq(root, sp.intervals))
        target = util.clamp(target, 20, 2000)
        pcall(function()
          local cur = params:get("q_freq" .. i)
          set_safe("q_freq" .. i, cur + (target - cur) * 0.04 * agg)
        end)
      end
      -- minimal fold, lowest chaos
      if math.random() < 0.08 then
        local fold_target = sp.fold_range[1] + math.random() * (sp.fold_range[2] - sp.fold_range[1])
        nudge("q_fold", (fold_target - (params:get("q_fold") or 0.3)) * 0.05 * agg, 0, 1)
      end
      if math.random() < 0.08 then
        local chaos_target = sp.chaos_range[1] + math.random() * (sp.chaos_range[2] - sp.chaos_range[1])
        nudge("chaos", (chaos_target - (params:get("chaos") or 0.3)) * 0.04 * agg, 0, 1)
      end
      -- maximum gong decay (long resonance)
      if math.random() < 0.1 then
        local dec = sp.gong_decay_range[1] + math.random() * (sp.gong_decay_range[2] - sp.gong_decay_range[1])
        set_safe("gong_decay", dec)
      end
      -- boost sub, quiet clicks
      if math.random() < 0.1 then
        nudge("sub_level", sp.sub_love * 0.03 * agg, 0, 1)
      end
      if math.random() < 0.08 then
        nudge("click_amp", -0.02 * agg, 0, 1)
      end
      -- long click decays
      if math.random() < 0.1 then
        local dec = sp.click_decay_range[1] + math.random() * (sp.click_decay_range[2] - sp.click_decay_range[1])
        set_safe("click_decay", dec)
      end
      -- engage tape feedback if playing
      if tape_playing and math.random() < 0.05 * agg then
        nudge("tape_feedback", 0.02 * agg, 0, 0.95)
      end
      -- gongs: gentle harmonic tuning
      if math.random() < 0.08 * agg then
        local gi = math.random(1, 4)
        local root = 80
        pcall(function() root = params:get("gong1") end)
        local target = snap_freq_to_scale(harmonic_freq(root, sp.intervals))
        target = util.clamp(target, 50, 5000)
        pcall(function()
          local cur = params:get("gong" .. gi)
          set_safe("gong" .. gi, cur + (target - cur) * 0.06 * agg)
        end)
      end
      -- bass: track scale at low octaves
      if math.random() < 0.08 * agg and #scale_notes > 0 then
        local note = scale_notes[math.random(1, math.min(3, #scale_notes))]
        set_safe("bass_freq", util.clamp(musicutil.note_num_to_freq(math.max(note - 24, 15)), 20, 200))
      end

    --------------------------------------------
    -- FOGO: fire rhythm
    --------------------------------------------
    elseif species_key == "fogo" then
      -- click rate locked to polyrhythmic ratios
      if math.random() < 0.2 * agg then
        local base_rate = 2
        pcall(function() base_rate = params:get("click_rate") end)
        local ratio = POLY_RATIOS[math.random(1, #POLY_RATIOS)]
        local target = util.clamp(base_rate * ratio, 0.1, 40)
        set_safe("click_rate", target)
      end
      -- rolz rates set to polyrhythmic ratios of each other
      if math.random() < 0.25 * agg then
        local base_r = 1
        pcall(function() base_r = params:get("rolz_r1") end)
        local i = math.random(2, 4)
        local ratio = POLY_RATIOS[math.random(1, #POLY_RATIOS)]
        set_safe("rolz_r" .. i, util.clamp(base_r * ratio, 0.01, 20))
      end
      -- increase rolz_to_click and cascade
      if math.random() < 0.2 * agg then
        nudge("rolz_to_click", 0.03 * agg, 0, 1)
      end
      if math.random() < 0.15 * agg then
        nudge("rolz_cascade", 0.025 * agg, 0, 1)
      end
      -- short percussive decays
      if math.random() < 0.15 * agg then
        local dec = sp.click_decay_range[1] + math.random() * (sp.click_decay_range[2] - sp.click_decay_range[1])
        set_safe("click_decay", dec)
      end
      -- fold and chaos in species range
      if math.random() < 0.15 then
        local fold_target = sp.fold_range[1] + math.random() * (sp.fold_range[2] - sp.fold_range[1])
        nudge("q_fold", (fold_target - (params:get("q_fold") or 0.3)) * 0.12 * agg, 0, 1)
      end
      if math.random() < 0.12 then
        local chaos_target = sp.chaos_range[1] + math.random() * (sp.chaos_range[2] - sp.chaos_range[1])
        nudge("chaos", (chaos_target - (params:get("chaos") or 0.3)) * 0.1 * agg, 0, 1)
      end
      -- bass body tuned to scale, rhythmic
      if math.random() < 0.15 * agg and #scale_notes > 0 then
        local note = scale_notes[math.random(1, math.min(7, #scale_notes))]
        local bass_freq = musicutil.note_num_to_freq(math.max(note - 12, 20))
        set_safe("bass_freq", util.clamp(bass_freq, 20, 200))
        set_safe("bass_click_pitch", util.clamp(bass_freq * 1.5, 20, 400))
      end
      -- gong tuning: percussive
      if math.random() < 0.1 * agg then
        local gi = math.random(1, 4)
        local root = 150
        pcall(function() root = params:get("gong1") end)
        local target = harmonic_freq(root, sp.intervals)
        set_safe("gong" .. gi, util.clamp(target, 50, 5000))
      end
      -- gong decay: short to medium
      if math.random() < 0.08 then
        local dec = sp.gong_decay_range[1] + math.random() * (sp.gong_decay_range[2] - sp.gong_decay_range[1])
        set_safe("gong_decay", dec)
      end
      -- quantussy: tune to scale with snap
      if math.random() < 0.15 * agg then
        local i = math.random(1, 5)
        local root = 55
        pcall(function() root = params:get("q_freq1") end)
        local target = snap_freq_to_scale(harmonic_freq(root, sp.intervals))
        target = util.clamp(target, 20, 2000)
        set_safe("q_freq" .. i, target)
      end
    end

    --------------------------------------------
    -- memory system: save snapshot every 16 ticks
    --------------------------------------------
    if L.tick % 16 == 0 then
      local snapshot = {}
      pcall(function()
        for i = 1, 5 do snapshot["q_freq" .. i] = params:get("q_freq" .. i) end
        snapshot.q_cross = params:get("q_cross")
        snapshot.q_fold = params:get("q_fold")
        snapshot.chaos = params:get("chaos")
        snapshot.click_rate = params:get("click_rate")
        snapshot.click_decay = params:get("click_decay")
        for i = 1, 4 do snapshot["gong" .. i] = params:get("gong" .. i) end
        snapshot.gong_decay = params:get("gong_decay")
        for i = 1, 4 do snapshot["rolz_r" .. i] = params:get("rolz_r" .. i) end
        snapshot.rolz_cascade = params:get("rolz_cascade")
        snapshot.rolz_to_click = params:get("rolz_to_click")
      end)
      table.insert(L.memory, snapshot)
      if #L.memory > 32 then table.remove(L.memory, 1) end
      -- occasionally mark as "best" (random preference)
      if math.random() < 0.15 then
        L.best_memory = snapshot
      end
    end

    -- occasionally recall a good configuration
    if L.best_memory and math.random() < 0.03 * agg and L.tick > 32 then
      local mem = L.best_memory
      for k, v in pairs(mem) do
        pcall(function()
          local cur = params:get(k)
          set_safe(k, cur + (v - cur) * 0.2 * agg)
        end)
      end
    end

    -- sleep based on rhythm style
    local sleep_time
    if sp.rhythm_style == "steady" then
      sleep_time = math.max(clock.get_beat_sec(), 0.05)
    elseif sp.rhythm_style == "erratic" then
      sleep_time = math.max(clock.get_beat_sec() * (0.3 + math.random() * 1.4), 0.05)
    elseif sp.rhythm_style == "sparse" then
      sleep_time = math.max(clock.get_beat_sec() * (1.5 + math.random() * 2.0), 0.05)
    elseif sp.rhythm_style == "polyrhythm" then
      local ratio = POLY_RATIOS[math.random(1, #POLY_RATIOS)]
      sleep_time = math.max(clock.get_beat_sec() * ratio, 0.05)
    else
      sleep_time = math.max(clock.get_beat_sec(), 0.05)
    end
    clock.sleep(sleep_time)
  end
end

function update_all_lagartas()
  for species_key, L in pairs(lagartas) do
    if L and L.active then
      local sp = L.spec

      -- movement
      local wobble = sp.speed * 0.5

      -- species-specific movement style
      if species_key == "verde" then
        -- gentle sine-wave undulation
        L.dx = L.dx + math.sin(frame * 0.03) * wobble * 0.08
        L.dy = L.dy + math.cos(frame * 0.025) * wobble * 0.06
      elseif species_key == "venenosa" then
        -- jagged movement
        L.dx = L.dx + (math.random() - 0.5) * wobble * 0.4
        L.dy = L.dy + (math.random() - 0.5) * wobble * 0.3
      elseif species_key == "seda" then
        -- floating motion
        L.dx = L.dx + math.sin(frame * 0.012 + 1.7) * wobble * 0.03
        L.dy = L.dy + math.cos(frame * 0.01 + 0.5) * wobble * 0.025
      elseif species_key == "fogo" then
        -- bouncy
        L.dx = L.dx + (math.random() - 0.5) * wobble * 0.25
        L.dy = L.dy + math.sin(frame * 0.08) * wobble * 0.2
      end

      L.dx = util.clamp(L.dx, -1.2, 1.2)
      L.dy = util.clamp(L.dy, -0.7, 0.7)

      L.x = L.x + L.dx
      L.y = L.y + L.dy

      -- bounce off edges
      if L.x < 4 then L.x = 4; L.dx = math.abs(L.dx) end
      if L.x > 124 then L.x = 124; L.dx = -math.abs(L.dx) end
      if L.y < 14 then L.y = 14; L.dy = math.abs(L.dy) end
      if L.y > 56 then L.y = 56; L.dy = -math.abs(L.dy) end

      -- update segments (follow the head)
      L.segments[1].x = L.x
      L.segments[1].y = L.y
      for i = 2, sp.seg_count do
        if L.segments[i] then
          local prev = L.segments[i-1]
          local seg = L.segments[i]
          local sdx = prev.x - seg.x
          local sdy = prev.y - seg.y
          local dist = math.sqrt(sdx * sdx + sdy * sdy)
          local spacing = species_key == "seda" and 2.5 or 3.5
          if dist > spacing then
            local ratio = spacing / dist
            seg.x = prev.x - sdx * ratio
            seg.y = prev.y - sdy * ratio
          end
        end
      end

      -- particles (venenosa sparks, seda dust, fogo sparks)
      if species_key == "venenosa" and math.random() < 0.3 then
        table.insert(L.particles, {
          x = L.x + math.random(-4, 4),
          y = L.y + math.random(-4, 4),
          life = 8 + math.random(0, 6),
          kind = "spark"
        })
      elseif species_key == "seda" and math.random() < 0.4 then
        local tail = L.segments[sp.seg_count]
        if tail then
          table.insert(L.particles, {
            x = tail.x + (math.random() - 0.5) * 3,
            y = tail.y + (math.random() - 0.5) * 2,
            life = 12 + math.random(0, 8),
            kind = "dust"
          })
        end
      elseif species_key == "fogo" and math.random() < 0.35 then
        table.insert(L.particles, {
          x = L.x + math.random(-3, 3),
          y = L.y + math.random(-5, 2),
          life = 5 + math.random(0, 4),
          kind = "fire"
        })
      end

      -- decay particles
      local new_particles = {}
      for _, p in ipairs(L.particles) do
        p.life = p.life - 1
        if p.kind == "dust" then
          p.y = p.y - 0.1
          p.x = p.x + (math.random() - 0.5) * 0.3
        elseif p.kind == "fire" then
          p.y = p.y - 0.3
          p.x = p.x + (math.random() - 0.5) * 0.5
        elseif p.kind == "spark" then
          p.x = p.x + (math.random() - 0.5) * 0.8
          p.y = p.y + (math.random() - 0.5) * 0.8
        end
        if p.life > 0 then
          table.insert(new_particles, p)
        end
      end
      L.particles = new_particles
      -- cap particles
      if #L.particles > 30 then
        local trimmed = {}
        for i = #L.particles - 29, #L.particles do
          table.insert(trimmed, L.particles[i])
        end
        L.particles = trimmed
      end
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

function safe_gesture_clock()
  clock.sleep(1)
  while true do
    clock.sleep(math.max(clock.get_beat_sec(), 0.05) / 4)
    local beats = clock.get_beats()
    if beats then
      local bars = ({2, 4, 8, 16})[params:get("gesture_bars")]
      local beat_pos = beats % (bars * 4)
      for layer = 1, 4 do
        if gesture_playing[layer] and #gesture_layers[layer] > 0 then
          for _, ev in ipairs(gesture_layers[layer]) do
            if math.abs(ev.time - beat_pos) < 0.04 then
              pcall(function() params:set(ev.param_id, ev.value) end)
            end
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
    if n == 2 then params:delta("click_pitch", d)
    elseif n == 3 then params:delta("click_ring", d) end
    record_gesture(n == 2 and "click_pitch" or "click_ring",
      params:get(n == 2 and "click_pitch" or "click_ring"))
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
    if n == 2 then
      -- cycle selected caterpillar
      cat_selected = util.clamp(cat_selected + d, 1, #SPECIES_ORDER)
    elseif n == 3 then
      -- adjust aggression
      params:delta("cat_aggression", d)
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
      -- toggle selected caterpillar on/off
      local sp_key = SPECIES_ORDER[cat_selected]
      local param_name = "cat_" .. sp_key
      local current = params:get(param_name)
      params:set(param_name, current == 1 and 2 or 1)
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
  elseif page == 6 then draw_lagartas() end

  -- chaos burst sparks
  if chaos_burst > 0.05 then
    screen.level(math.floor(chaos_burst * 10))
    for _ = 1, math.floor(chaos_burst * 15) do
      screen.pixel(math.random(0, 127), math.random(10, 63))
    end
    screen.fill()
  end

  -- lagarta active indicator (small worms on all pages)
  if page ~= 6 then
    local any_active = false
    for _, sp_key in ipairs(SPECIES_ORDER) do
      if lagartas[sp_key] then any_active = true; break end
    end
    if any_active then
      screen.level(4 + math.floor(math.sin(frame * 0.15) * 3))
      local ix = 122 + math.sin(frame * 0.1) * 2
      screen.circle(ix, 4, 1.5)
      screen.fill()
      screen.circle(ix + 3, 4 + math.sin(frame * 0.2), 1)
      screen.fill()
    end
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
    {l="pitch", v=string.format("%.0f", pitch),                     y=18},
    {l="ring",  v=string.format("%.2f", ring),                      y=28},
    {l="rate",  v=string.format("%.1f", params:get("click_rate")),  y=38},
    {l="decay", v=string.format("%.3f", decay),                     y=48},
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
-- page 6: LAGARTAS (multi-personality caterpillars)
------------------------------------------------------------

function draw_lagartas()
  -- count active
  local any_active = false
  for _, sp_key in ipairs(SPECIES_ORDER) do
    if lagartas[sp_key] then any_active = true; break end
  end

  if not any_active then
    -- sleeping state
    screen.level(4)
    screen.font_size(8)
    screen.move(20, 30)
    screen.text("K2 to wake a lagarta")
    screen.move(20, 42)
    screen.text("E2 select  E3 aggression")
    -- show species selector
    for i, sp_key in ipairs(SPECIES_ORDER) do
      local sp = SPECIES[sp_key]
      local sel = (i == cat_selected)
      screen.level(sel and 12 or 3)
      screen.move(2 + (i - 1) * 32, 56)
      screen.font_size(6)
      screen.text(sp.name)
    end
    -- small sleeping worm
    for i = 1, 6 do
      local bri = math.floor(2 + math.sin(frame * 0.05 + i * 0.5) * 1.5)
      screen.level(util.clamp(bri, 1, 4))
      screen.circle(50 + i * 4, 18 + math.sin(frame * 0.03 + i * 0.3) * 1, 2)
      screen.fill()
    end
    return
  end

  -- draw each active lagarta
  for _, sp_key in ipairs(SPECIES_ORDER) do
    local L = lagartas[sp_key]
    if L and L.active then
      local sp = L.spec

      -- draw particles first (behind body)
      for _, p in ipairs(L.particles) do
        if p.kind == "spark" then
          screen.level(util.clamp(math.floor(p.life * 1.2), 1, 15))
          screen.pixel(math.floor(p.x), math.floor(p.y))
          screen.fill()
        elseif p.kind == "dust" then
          screen.level(util.clamp(math.floor(p.life * 0.3), 1, 4))
          screen.pixel(math.floor(p.x), math.floor(p.y))
          screen.fill()
        elseif p.kind == "fire" then
          screen.level(util.clamp(math.floor(p.life * 1.5), 1, 15))
          screen.pixel(math.floor(p.x), math.floor(p.y))
          screen.fill()
          -- extra brightness near head
          if p.life > 3 then
            screen.pixel(math.floor(p.x) + 1, math.floor(p.y))
            screen.fill()
          end
        end
      end

      -- draw body segments with legs, texture, and anatomy
      local agg = 0.5
      pcall(function() agg = params:get("cat_aggression") end)

      for i = sp.seg_count, 1, -1 do
        local seg = L.segments[i]
        if not seg then goto continue_seg end
        local prev_seg = L.segments[i-1]
        local next_seg = L.segments[i+1]

        local param_intensity = 0
        if i <= 5 then param_intensity = math.abs(math.sin(q_phase[i] or 0))
        elseif i == 6 then param_intensity = click_flash
        elseif i == 7 then param_intensity = math.max(gong_rings[1] or 0, gong_rings[2] or 0)
        elseif i <= 10 then param_intensity = rolz_flash[i - 7] or 0 end

        local bri = util.clamp(math.floor(sp.bright_base + param_intensity * 5
          + math.sin(frame * 0.1 + i * 0.5) * 1.5 + agg * 3), 1, 15)

        -- body direction for leg angle
        local body_angle = 0
        if prev_seg then
          body_angle = math.atan2(prev_seg.y - seg.y, prev_seg.x - seg.x)
        end
        local perp = body_angle + math.pi / 2

        if sp_key == "verde" then
          -- lush round body with visible segment ridges
          local uy = seg.y + math.sin(frame * 0.06 + i * 0.5) * 1.5
          local r = i == 1 and 3.5 or (2.8 - i * 0.12)
          r = math.max(r, 1.0)
          -- body fill
          screen.level(bri)
          screen.circle(seg.x, uy, r)
          screen.fill()
          -- segment ridge highlight (brighter top arc)
          screen.level(util.clamp(bri + 3, 1, 15))
          screen.arc(seg.x, uy, r * 0.8, math.pi * 1.1, math.pi * 1.9)
          screen.stroke()
          -- tiny legs on non-head segments (alternating phase)
          if i > 1 and i < sp.seg_count then
            screen.level(util.clamp(bri - 2, 1, 10))
            local leg_phase = math.sin(frame * 0.08 + i * 0.6) * 1.5
            -- left leg
            screen.move(seg.x + math.cos(perp) * r * 0.6, uy + math.sin(perp) * r * 0.6)
            screen.line(seg.x + math.cos(perp) * (r + 2.5), uy + math.sin(perp) * (r + 2.5) + leg_phase)
            screen.stroke()
            -- right leg
            screen.move(seg.x - math.cos(perp) * r * 0.6, uy - math.sin(perp) * r * 0.6)
            screen.line(seg.x - math.cos(perp) * (r + 2.5), uy - math.sin(perp) * (r + 2.5) - leg_phase)
            screen.stroke()
          end

        elseif sp_key == "venenosa" then
          -- spiky armored segments with thorns
          local uy = seg.y + (math.random() - 0.5) * 1.2
          local r = i == 1 and 3.2 or (2.5 - i * 0.08)
          r = math.max(r, 0.8)
          -- diamond body
          screen.level(bri)
          screen.move(seg.x, uy - r)
          screen.line(seg.x + r * 1.2, uy)
          screen.line(seg.x, uy + r)
          screen.line(seg.x - r * 1.2, uy)
          screen.close()
          screen.fill()
          -- dorsal spines
          if i > 1 then
            screen.level(util.clamp(bri + 2, 1, 15))
            local spine_h = r * 0.8 + math.random() * 1.5
            screen.move(seg.x, uy - r)
            screen.line(seg.x + (math.random() - 0.5) * 1.5, uy - r - spine_h)
            screen.stroke()
          end
          -- jagged legs
          if i > 1 and i < sp.seg_count then
            screen.level(util.clamp(bri - 1, 1, 12))
            local jag = (math.random() - 0.5) * 2
            screen.move(seg.x + r * 0.8, uy + r * 0.3)
            screen.line(seg.x + r + 2.5 + jag, uy + r + 1.5)
            screen.stroke()
            screen.move(seg.x - r * 0.8, uy + r * 0.3)
            screen.line(seg.x - r - 2.5 - jag, uy + r + 1.5)
            screen.stroke()
          end

        elseif sp_key == "seda" then
          -- ethereal translucent body with glowing core
          local uy = seg.y + math.sin(frame * 0.04 + i * 0.6) * 2.5
          local r = i == 1 and 2.0 or (1.5 - i * 0.04)
          r = math.max(r, 0.5)
          -- outer glow (dim)
          screen.level(util.clamp(math.floor(bri * 0.4), 1, 4))
          screen.circle(seg.x, uy, r + 1.5)
          screen.stroke()
          -- inner core (brighter)
          screen.level(util.clamp(bri, 1, 7))
          screen.circle(seg.x, uy, r)
          screen.fill()
          -- connecting thread between segments
          if next_seg then
            local nuy = next_seg.y + math.sin(frame * 0.04 + (i+1) * 0.6) * 2.5
            screen.level(util.clamp(math.floor(bri * 0.3), 1, 3))
            screen.move(seg.x, uy)
            screen.line(next_seg.x, nuy)
            screen.stroke()
          end

        elseif sp_key == "fogo" then
          -- pulsing ember segments, size breathes with rhythm
          local pulse = click_flash * 3 + (rolz_flash[1] or 0) * 2
          local final_bri = util.clamp(math.floor(bri + pulse * 3), 1, 15)
          local r = i == 1 and 3.0 or (2.2 - i * 0.1)
          r = math.max(r, 0.7)
          -- size pulses with rhythm
          r = r + pulse * 0.8
          local bounce = math.abs(math.sin(frame * 0.12 + i * 0.4)) * 2.0
          local uy = seg.y - bounce
          -- hot core
          screen.level(final_bri)
          screen.circle(seg.x, uy, r)
          screen.fill()
          -- outer heat ring
          screen.level(util.clamp(math.floor(final_bri * 0.5), 1, 8))
          screen.circle(seg.x, uy, r + 1)
          screen.stroke()
          -- legs that kick with rhythm
          if i > 1 and i < sp.seg_count then
            screen.level(util.clamp(final_bri - 2, 1, 12))
            local kick = math.sin(frame * 0.15 + i) * 2
            screen.move(seg.x + r * 0.5, uy + r * 0.5)
            screen.line(seg.x + r + 2 + kick, uy + r + 2)
            screen.stroke()
            screen.move(seg.x - r * 0.5, uy + r * 0.5)
            screen.line(seg.x - r - 2 - kick, uy + r + 2)
            screen.stroke()
          end
        end
        ::continue_seg::
      end

      -- draw head details: antennae, mandibles, eyes
      local head = L.segments[1]
      if head then
        local ant_len = 5 + math.sin(frame * 0.12) * 2

        if sp_key == "verde" then
          -- graceful curved antennae with bulb tips
          screen.level(8)
          local la_x = head.x - ant_len * 0.7 + math.sin(frame * 0.1) * 2
          local la_y = head.y - 3 - ant_len + math.cos(frame * 0.13) * 1.5
          local ra_x = head.x + ant_len * 0.7 + math.cos(frame * 0.09) * 2
          local ra_y = head.y - 3 - ant_len + math.sin(frame * 0.11) * 1.5
          -- curved antennae via control point
          screen.move(head.x - 1, head.y - 3)
          screen.curve(head.x - 3, head.y - 4 - ant_len * 0.5,
                       la_x + 1, la_y + 2, la_x, la_y)
          screen.stroke()
          screen.move(head.x + 1, head.y - 3)
          screen.curve(head.x + 3, head.y - 4 - ant_len * 0.5,
                       ra_x - 1, ra_y + 2, ra_x, ra_y)
          screen.stroke()
          -- bulb tips
          screen.level(10)
          screen.circle(la_x, la_y, 1.2)
          screen.fill()
          screen.circle(ra_x, ra_y, 1.2)
          screen.fill()
          -- small mandibles
          screen.level(5)
          screen.move(head.x - 1.5, head.y + 2)
          screen.line(head.x - 2.5, head.y + 3.5)
          screen.stroke()
          screen.move(head.x + 1.5, head.y + 2)
          screen.line(head.x + 2.5, head.y + 3.5)
          screen.stroke()

        elseif sp_key == "venenosa" then
          -- long sharp antennae, fangs
          screen.level(13)
          local spread = ant_len * 0.9
          local la_x = head.x - spread
          local la_y = head.y - 3 - ant_len * 1.3
          local ra_x = head.x + spread
          local ra_y = head.y - 3 - ant_len * 1.3
          screen.move(head.x - 1, head.y - 2)
          screen.line(la_x, la_y)
          screen.stroke()
          screen.move(head.x + 1, head.y - 2)
          screen.line(ra_x, ra_y)
          screen.stroke()
          -- fangs / mandibles
          screen.level(15)
          screen.move(head.x - 1, head.y + 1.5)
          screen.line(head.x - 3, head.y + 5)
          screen.line(head.x - 0.5, head.y + 3)
          screen.stroke()
          screen.move(head.x + 1, head.y + 1.5)
          screen.line(head.x + 3, head.y + 5)
          screen.line(head.x + 0.5, head.y + 3)
          screen.stroke()

        elseif sp_key == "seda" then
          -- gossamer thread antennae, barely there
          screen.level(3)
          local sway = math.sin(frame * 0.03) * 3
          screen.move(head.x, head.y - 1)
          screen.line(head.x - 3 + sway, head.y - 2 - ant_len * 0.8)
          screen.stroke()
          screen.move(head.x, head.y - 1)
          screen.line(head.x + 3 - sway, head.y - 2 - ant_len * 0.8)
          screen.stroke()
          -- tiny glowing tips
          screen.level(5)
          screen.pixel(math.floor(head.x - 3 + sway), math.floor(head.y - 2 - ant_len * 0.8))
          screen.fill()
          screen.pixel(math.floor(head.x + 3 - sway), math.floor(head.y - 2 - ant_len * 0.8))
          screen.fill()

        elseif sp_key == "fogo" then
          -- flame antennae that flicker
          screen.level(13)
          local flicker_l = math.sin(frame * 0.2) * 2 + math.random() * 1
          local flicker_r = math.cos(frame * 0.18) * 2 + math.random() * 1
          screen.move(head.x - 1, head.y - 2)
          screen.line(head.x - ant_len * 0.5 + flicker_l, head.y - 3 - ant_len)
          screen.stroke()
          screen.move(head.x + 1, head.y - 2)
          screen.line(head.x + ant_len * 0.5 + flicker_r, head.y - 3 - ant_len)
          screen.stroke()
          -- flame tips
          screen.level(15)
          screen.circle(head.x - ant_len * 0.5 + flicker_l, head.y - 3 - ant_len, 0.8)
          screen.fill()
          screen.circle(head.x + ant_len * 0.5 + flicker_r, head.y - 3 - ant_len, 0.8)
          screen.fill()
          -- ember mandibles
          screen.level(10)
          screen.move(head.x - 1, head.y + 2)
          screen.line(head.x - 2, head.y + 4)
          screen.stroke()
          screen.move(head.x + 1, head.y + 2)
          screen.line(head.x + 2, head.y + 4)
          screen.stroke()
        end

        -- eyes (species-specific)
        if sp_key == "venenosa" then
          -- angry red eyes (bright, larger)
          screen.level(15)
          screen.circle(head.x - 1.5, head.y - 0.5, 0.9)
          screen.fill()
          screen.circle(head.x + 1.5, head.y - 0.5, 0.9)
          screen.fill()
        elseif sp_key == "seda" then
          -- dim gentle eyes
          screen.level(5)
          screen.circle(head.x - 1, head.y, 0.5)
          screen.fill()
          screen.circle(head.x + 1, head.y, 0.5)
          screen.fill()
        elseif sp_key == "fogo" then
          -- glowing ember eyes
          local eye_bri = util.clamp(math.floor(10 + click_flash * 5), 1, 15)
          screen.level(eye_bri)
          screen.circle(head.x - 1.5, head.y - 0.3, 0.7)
          screen.fill()
          screen.circle(head.x + 1.5, head.y - 0.3, 0.7)
          screen.fill()
        else
          -- verde: friendly round eyes
          screen.level(12)
          screen.circle(head.x - 1.5, head.y - 0.5, 0.8)
          screen.fill()
          screen.circle(head.x + 1.5, head.y - 0.5, 0.8)
          screen.fill()
          -- pupils
          screen.level(0)
          screen.circle(head.x - 1.5, head.y - 0.3, 0.3)
          screen.fill()
          screen.circle(head.x + 1.5, head.y - 0.3, 0.3)
          screen.fill()
        end

        -- species label
        screen.level(util.clamp(sp.bright_base, 1, 10))
        screen.font_size(6)
        screen.move(head.x + 5, head.y - 4)
        screen.text(sp.name)
      end
    end
  end

  -- bottom bar: show which species are active, selected species highlighted
  screen.font_size(6)
  for i, sp_key in ipairs(SPECIES_ORDER) do
    local sp = SPECIES[sp_key]
    local is_active = lagartas[sp_key] ~= nil
    local is_sel = (i == cat_selected)
    if is_active then
      screen.level(is_sel and 15 or 8)
    else
      screen.level(is_sel and 6 or 2)
    end
    screen.move(1 + (i - 1) * 32, 63)
    screen.text(sp.name)
    if is_active then
      -- small dot indicator
      screen.level(sp.bright_base)
      screen.circle(28 + (i - 1) * 32, 61, 1)
      screen.fill()
    end
  end

  -- aggression display
  screen.level(6)
  screen.font_size(6)
  local agg_val = 0.5
  pcall(function() agg_val = params:get("cat_aggression") end)
  screen.move(108, 11)
  screen.text(string.format("%.1f", agg_val))
end

------------------------------------------------------------
-- cleanup
------------------------------------------------------------

function cleanup()
  -- stop all lagarta clocks
  for sp_key, L in pairs(lagartas) do
    if L and L.clock_id then
      pcall(function() clock.cancel(L.clock_id) end)
      L.clock_id = nil
    end
    if L then L.active = false end
  end
  lagartas = {}

  softcut.rec(1, 0)
  softcut.play(1, 0)
  softcut.play(2, 0)
  softcut.poll_stop_phase()
  if midi_out then
    midi_out:cc(123, 0, params:get("midi_channel"))
  end
  if g and g.device then g:all(0); g:refresh() end
end
