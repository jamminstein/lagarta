// Engine_Lagarta
// Ciat-Lonbarde synthesis for norns
//
// Six interacting sections:
//   QUANTUSSY - 5 cross-modulated bounds oscillators in a ring
//   SUB       - sub bass tracking quantussy fundamentals
//   ROLZ      - 4 chaotic rhythm oscillators with cascading comparators
//   CLICKER   - dual impulse voices with ring modulation
//   GONGS     - resonant bodies excited by clicks (tuned low to high)
//   INPUT     - external audio through wavefolder and gongs
//
// Inspired by Peter Blasser's paper circuits

Engine_Lagarta : CroneEngine {
  var synth;

  *new { arg context, doneCallback;
    ^super.new(context, doneCallback);
  }

  alloc {
    SynthDef(\lagarta, {
      arg out=0, amp=0.5,
        // quantussy ring
        q_freq1=36, q_freq2=55, q_freq3=82, q_freq4=131, q_freq5=196,
        q_bounds=0.5, q_cross=0.3, q_mix=0.25, q_fold=0.5,
        // sub bass
        sub_freq=36, sub_level=0.15, sub_width=0.3,
        // rolz (Plumbutter-style chaotic rhythm)
        rolz_r1=1.0, rolz_r2=2.3, rolz_r3=4.7, rolz_r4=0.6,
        rolz_cascade=0.5, rolz_to_click=0.3,
        // bass body (low resonator excited by rolz/clicks)
        bass_freq=55, bass_decay=0.25, bass_level=0.2,
        // bass clicker (low-frequency melodic clicks)
        bass_click_pitch=80, bass_click_decay=0.08, bass_click_amp=0.4,
        // clicker
        click_rate=4, click_decay=0.06, click_pitch=300,
        click_ring=0.4, click_amp=0.7, click_free=1,
        t_click=0,
        // gongs (now spanning low to high)
        gong1=80, gong2=220, gong3=580, gong4=1200,
        gong_decay=2.0, gong_amp=0.5,
        // audio input
        input_gain=0, input_fold=0, input_to_gong=0, input_mix=0,
        // mixer levels (per voice, 0=mute to 2=boost)
        mix_quantussy=0.25, mix_sub=0.15, mix_bass_body=0.2,
        mix_bass_click=0.4, mix_clicker=0.7, mix_gongs=0.5,
        // 3-band EQ
        eq_lo_freq=120, eq_lo_gain=0, eq_lo_rs=1,
        eq_mid_freq=1000, eq_mid_gain=0, eq_mid_rq=0.7,
        eq_hi_freq=5000, eq_hi_gain=0, eq_hi_rs=1,
        // master
        lpf_freq=3500, lpf_res=0.1,
        saturation=0.5, stereo_width=0.25,
        // global
        chaos=0.3, drift=0.1;

      var fb, q1, q2, q3, q4, q5, quantussy;
      var sub;
      var r1, r2, r3, r4, r1_trig, r2_trig, r3_trig, r4_trig, rolz_trig;
      var bass_body, all_trig;
      var int_trig, ext_trig, dust_trig, trig;
      var click_env, click1, click2, clicker;
      var bass_click_env, bass_click;
      var gong_in, gongs;
      var input_sig, input_folded;
      var sig;

      // ---- QUANTUSSY RING ----
      // 5 oscillators in a feedback ring — now starting deeper
      // osc1 at 36 Hz = deep sub territory
      // VarSaw models the triangle-core bounds oscillator

      fb = LocalIn.ar(1, 0);

      q1 = VarSaw.ar(
        (q_freq1 * (1 + (fb * q_cross * 0.5)
          + (LFNoise2.kr(0.1 + (drift * 3)) * drift * 0.1))).max(1),
        0,
        LFNoise1.kr(0.3).range(0.05, 0.95)
      );
      q2 = VarSaw.ar(
        (q_freq2 * (1 + (q1 * q_cross * 0.5)
          + (LFNoise2.kr(0.13 + (drift * 3)) * drift * 0.12))).max(1),
        0,
        LFNoise1.kr(0.37).range(0.05, 0.95)
      );
      q3 = VarSaw.ar(
        (q_freq3 * (1 + (q2 * q_cross * 0.5)
          + (LFNoise2.kr(0.17 + (drift * 3)) * drift * 0.14))).max(1),
        0,
        LFNoise1.kr(0.43).range(0.05, 0.95)
      );
      q4 = VarSaw.ar(
        (q_freq4 * (1 + (q3 * q_cross * 0.5)
          + (LFNoise2.kr(0.19 + (drift * 3)) * drift * 0.16))).max(1),
        0,
        LFNoise1.kr(0.53).range(0.05, 0.95)
      );
      q5 = VarSaw.ar(
        (q_freq5 * (1 + (q4 * q_cross * 0.5)
          + (LFNoise2.kr(0.23 + (drift * 3)) * drift * 0.18))).max(1),
        0,
        LFNoise1.kr(0.67).range(0.05, 0.95)
      );

      LocalOut.ar([q5]);

      quantussy = Mix([q1, q2, q3, q4, q5]) * 0.2;
      quantussy = Fold.ar(quantussy * (1 + (q_fold * 4)), q_bounds.neg, q_bounds);
      quantussy = quantussy * q_mix;

      // ---- SUB BASS ----
      // dedicated sub oscillator — Lua updates sub_freq with scale notes
      // sine + pulse hybrid for thickness
      // uses Dust for rhythmic breathing (independent of clicker trig)

      sub = SinOsc.ar(
        sub_freq + (LFNoise2.kr(0.07) * drift * 2)
          + (EnvGen.kr(Env.perc(0.001, 0.1), Dust.kr(click_rate.max(1))) * sub_freq * 0.05),
        0,
        sub_level * 0.6
      );
      // pulse sub at same freq for harmonic grit
      sub = sub + (
        Pulse.ar(
          sub_freq + (LFNoise2.kr(0.05) * drift),
          sub_width + (LFNoise1.kr(0.2) * 0.1)
        ) * sub_level * 0.25
      );
      // slight amplitude pulse — sub breathes with the rhythm
      sub = sub * (1 + (EnvGen.kr(Env.perc(0.001, 0.3), Dust.kr(click_rate.max(1))) * 0.3));
      sub = LPF.ar(sub, (sub_freq * 4).min(400));

      // ---- ROLZ ----
      // Plumbutter-style cascading rhythm oscillators

      r1 = LFSaw.ar(rolz_r1 + (LFNoise2.kr(0.07) * drift * rolz_r1 * 0.1));
      r1_trig = Trig1.ar(r1 - 0, SampleDur.ir * 2);

      r2 = LFSaw.ar(rolz_r2 + (r1_trig * rolz_cascade * rolz_r2 * 0.5)
        + (LFNoise2.kr(0.09) * drift * rolz_r2 * 0.1));
      r2_trig = Trig1.ar(r2 - 0, SampleDur.ir * 2);

      r3 = LFSaw.ar(rolz_r3 + (r2_trig * rolz_cascade * rolz_r3 * 0.5)
        + (LFNoise2.kr(0.11) * drift * rolz_r3 * 0.1));
      r3_trig = Trig1.ar(r3 - 0, SampleDur.ir * 2);

      r4 = LFSaw.ar(rolz_r4 + (r3_trig * rolz_cascade * rolz_r4 * 0.5)
        + (LFNoise2.kr(0.13) * drift * rolz_r4 * 0.1));
      r4_trig = Trig1.ar(r4 - 0, SampleDur.ir * 2);

      rolz_trig = (r1_trig + r2_trig + r3_trig + r4_trig) * rolz_to_click;

      // ---- BASS BODY ----
      // low resonant body excited by rolz triggers and clicker
      // like a kick drum membrane — short decay, deep frequency
      // Plumbutter's bass drum lives here

      all_trig = rolz_trig + Trig1.ar(K2A.ar(t_click), SampleDur.ir);
      bass_body = Ringz.ar(
        EnvGen.ar(Env.perc(0.0001, 0.01), all_trig + Dust.ar(chaos * 2)),
        bass_freq + (LFNoise2.kr(0.1) * drift * 5),
        bass_decay
      );
      bass_body = (bass_body * bass_level).tanh;
      // extra sub punch: short sine burst
      bass_body = bass_body + (
        SinOsc.ar(bass_freq * 0.5) *
        EnvGen.ar(Env.perc(0.001, bass_decay * 0.5), all_trig) *
        bass_level * 0.5
      );

      // ---- CLICKER ----
      // now with lower default pitch for meatier clicks

      int_trig = Impulse.ar(
        click_rate + (Crackle.ar(1.5 + (chaos * 0.5)) * chaos * click_rate * 0.4)
      ) * click_free;
      ext_trig = Trig1.ar(K2A.ar(t_click), SampleDur.ir);
      dust_trig = Dust.ar(chaos * 8);
      trig = int_trig + ext_trig + dust_trig + rolz_trig;

      click_env = EnvGen.ar(Env.perc(0.0001, click_decay), trig);

      click1 = click_env * SinOsc.ar(
        (click_pitch + (quantussy * 200 * chaos)).max(20)
      );
      click2 = click_env * SinOsc.ar(
        (click_pitch * 1.618 + (quantussy * 300 * chaos)).max(20)
      );

      clicker = ((click1 * click2 * click_ring) + (click1 * (1 - click_ring))) * click_amp * 3;

      // ---- BASS CLICKER ----
      // melodic low-frequency click voice — fires on same triggers
      // longer decay than main clicker = more tonal, less percussive
      // pitch tracks bass_click_pitch (Lua updates this with scale notes)
      bass_click_env = EnvGen.ar(Env.perc(0.001, bass_click_decay), trig);
      bass_click = bass_click_env * SinOsc.ar(
        (bass_click_pitch + (quantussy * 30 * chaos)).max(20)
      );
      // add a sub-harmonic for weight
      bass_click = bass_click + (bass_click_env * SinOsc.ar(
        (bass_click_pitch * 0.5).max(15)
      ) * 0.6);
      bass_click = bass_click * bass_click_amp;

      // ---- GONGS ----
      // now spanning LOW to high: 80 Hz gong rumbles, 1200 Hz shimmers
      // the lowest gong provides sustained bass resonance

      gong_in = clicker + (dust_trig * 0.2);

      // ---- AUDIO INPUT ----
      input_sig = SoundIn.ar([0, 1]).sum * input_gain;
      input_folded = Fold.ar(input_sig * (1 + (input_fold * 4)), -0.5, 0.5);
      gong_in = gong_in + (input_folded * input_to_gong);

      gongs = Mix([
        Ringz.ar(gong_in, gong1 + (LFNoise2.kr(0.1) * drift * 5), gong_decay * 1.5),   // LOW gong — long decay
        Ringz.ar(gong_in, gong2 + (LFNoise2.kr(0.13) * drift * 15), gong_decay),
        Ringz.ar(gong_in, gong3 + (LFNoise2.kr(0.17) * drift * 30), gong_decay * 0.6),
        Ringz.ar(gong_in, gong4 + (LFNoise2.kr(0.19) * drift * 40), gong_decay * 0.35)
      ]) * 0.12 * gong_amp;

      // ---- MIXER ----
      // per-voice levels: 0=mute, 1=unity, 2=boost
      sig = (quantussy * mix_quantussy)
        + (bass_body * mix_bass_body)
        + (bass_click * mix_bass_click)
        + (clicker * mix_clicker)
        + (gongs * mix_gongs)
        + (input_folded * input_mix);
      sig = LeakDC.ar(sig);

      // ---- 3-BAND EQ ----
      // low shelf, parametric mid, high shelf
      sig = BLowShelf.ar(sig, eq_lo_freq, eq_lo_rs.max(0.1), eq_lo_gain.dbamp);
      sig = BPeakEQ.ar(sig, eq_mid_freq, eq_mid_rq.max(0.1), eq_mid_gain);
      sig = BHiShelf.ar(sig, eq_hi_freq, eq_hi_rs.max(0.1), eq_hi_gain.dbamp);

      // warmth filter
      sig = RLPF.ar(sig, lpf_freq, lpf_res.max(0.01));

      // ---- MASTER ----
      // saturation: 0=clean, 1=warm, >1=heavy
      sig = Select.ar(saturation > 0.01, [sig, (sig * (1 + saturation)).tanh]);

      sig = sig * amp;

      // stereo image: sub centered, rest panned with width control
      sig = Pan2.ar(sig, LFNoise2.kr(0.1 + (chaos * 0.5)).range(stereo_width.neg, stereo_width));
      // sub always mono center
      sig = sig + ((sub * mix_sub) ! 2);
      Out.ar(out, sig);
    }).add;

    context.server.sync;

    synth = Synth(\lagarta, [\out, context.out_b.index], context.xg);

    // ---- COMMANDS ----

    // quantussy
    this.addCommand("q_freq1", "f", { arg msg; synth.set(\q_freq1, msg[1]); });
    this.addCommand("q_freq2", "f", { arg msg; synth.set(\q_freq2, msg[1]); });
    this.addCommand("q_freq3", "f", { arg msg; synth.set(\q_freq3, msg[1]); });
    this.addCommand("q_freq4", "f", { arg msg; synth.set(\q_freq4, msg[1]); });
    this.addCommand("q_freq5", "f", { arg msg; synth.set(\q_freq5, msg[1]); });
    this.addCommand("q_bounds", "f", { arg msg; synth.set(\q_bounds, msg[1]); });
    this.addCommand("q_cross", "f", { arg msg; synth.set(\q_cross, msg[1]); });
    this.addCommand("q_mix", "f", { arg msg; synth.set(\q_mix, msg[1]); });
    this.addCommand("q_fold", "f", { arg msg; synth.set(\q_fold, msg[1]); });

    // sub
    this.addCommand("sub_freq", "f", { arg msg; synth.set(\sub_freq, msg[1]); });
    this.addCommand("sub_level", "f", { arg msg; synth.set(\sub_level, msg[1]); });
    this.addCommand("sub_width", "f", { arg msg; synth.set(\sub_width, msg[1]); });

    // rolz
    this.addCommand("rolz_r1", "f", { arg msg; synth.set(\rolz_r1, msg[1]); });
    this.addCommand("rolz_r2", "f", { arg msg; synth.set(\rolz_r2, msg[1]); });
    this.addCommand("rolz_r3", "f", { arg msg; synth.set(\rolz_r3, msg[1]); });
    this.addCommand("rolz_r4", "f", { arg msg; synth.set(\rolz_r4, msg[1]); });
    this.addCommand("rolz_cascade", "f", { arg msg; synth.set(\rolz_cascade, msg[1]); });
    this.addCommand("rolz_to_click", "f", { arg msg; synth.set(\rolz_to_click, msg[1]); });

    // bass body
    this.addCommand("bass_freq", "f", { arg msg; synth.set(\bass_freq, msg[1]); });
    this.addCommand("bass_decay", "f", { arg msg; synth.set(\bass_decay, msg[1]); });
    this.addCommand("bass_level", "f", { arg msg; synth.set(\bass_level, msg[1]); });

    // bass clicker
    this.addCommand("bass_click_pitch", "f", { arg msg; synth.set(\bass_click_pitch, msg[1]); });
    this.addCommand("bass_click_decay", "f", { arg msg; synth.set(\bass_click_decay, msg[1]); });
    this.addCommand("bass_click_amp", "f", { arg msg; synth.set(\bass_click_amp, msg[1]); });

    // clicker
    this.addCommand("click_rate", "f", { arg msg; synth.set(\click_rate, msg[1]); });
    this.addCommand("click_decay", "f", { arg msg; synth.set(\click_decay, msg[1]); });
    this.addCommand("click_pitch", "f", { arg msg; synth.set(\click_pitch, msg[1]); });
    this.addCommand("click_ring", "f", { arg msg; synth.set(\click_ring, msg[1]); });
    this.addCommand("click_amp", "f", { arg msg; synth.set(\click_amp, msg[1]); });
    this.addCommand("click_free", "f", { arg msg; synth.set(\click_free, msg[1]); });
    this.addCommand("trig", "f", { arg msg; synth.set(\t_click, msg[1]); });

    // gongs
    this.addCommand("gong1", "f", { arg msg; synth.set(\gong1, msg[1]); });
    this.addCommand("gong2", "f", { arg msg; synth.set(\gong2, msg[1]); });
    this.addCommand("gong3", "f", { arg msg; synth.set(\gong3, msg[1]); });
    this.addCommand("gong4", "f", { arg msg; synth.set(\gong4, msg[1]); });
    this.addCommand("gong_decay", "f", { arg msg; synth.set(\gong_decay, msg[1]); });
    this.addCommand("gong_amp", "f", { arg msg; synth.set(\gong_amp, msg[1]); });

    // audio input
    this.addCommand("input_gain", "f", { arg msg; synth.set(\input_gain, msg[1]); });
    this.addCommand("input_fold", "f", { arg msg; synth.set(\input_fold, msg[1]); });
    this.addCommand("input_to_gong", "f", { arg msg; synth.set(\input_to_gong, msg[1]); });
    this.addCommand("input_mix", "f", { arg msg; synth.set(\input_mix, msg[1]); });

    // mixer
    this.addCommand("mix_quantussy", "f", { arg msg; synth.set(\mix_quantussy, msg[1]); });
    this.addCommand("mix_sub", "f", { arg msg; synth.set(\mix_sub, msg[1]); });
    this.addCommand("mix_bass_body", "f", { arg msg; synth.set(\mix_bass_body, msg[1]); });
    this.addCommand("mix_bass_click", "f", { arg msg; synth.set(\mix_bass_click, msg[1]); });
    this.addCommand("mix_clicker", "f", { arg msg; synth.set(\mix_clicker, msg[1]); });
    this.addCommand("mix_gongs", "f", { arg msg; synth.set(\mix_gongs, msg[1]); });

    // eq
    this.addCommand("eq_lo_freq", "f", { arg msg; synth.set(\eq_lo_freq, msg[1]); });
    this.addCommand("eq_lo_gain", "f", { arg msg; synth.set(\eq_lo_gain, msg[1]); });
    this.addCommand("eq_mid_freq", "f", { arg msg; synth.set(\eq_mid_freq, msg[1]); });
    this.addCommand("eq_mid_gain", "f", { arg msg; synth.set(\eq_mid_gain, msg[1]); });
    this.addCommand("eq_hi_freq", "f", { arg msg; synth.set(\eq_hi_freq, msg[1]); });
    this.addCommand("eq_hi_gain", "f", { arg msg; synth.set(\eq_hi_gain, msg[1]); });

    // master
    this.addCommand("lpf_freq", "f", { arg msg; synth.set(\lpf_freq, msg[1]); });
    this.addCommand("lpf_res", "f", { arg msg; synth.set(\lpf_res, msg[1]); });
    this.addCommand("saturation", "f", { arg msg; synth.set(\saturation, msg[1]); });
    this.addCommand("stereo_width", "f", { arg msg; synth.set(\stereo_width, msg[1]); });

    // global
    this.addCommand("chaos", "f", { arg msg; synth.set(\chaos, msg[1]); });
    this.addCommand("drift", "f", { arg msg; synth.set(\drift, msg[1]); });
    this.addCommand("amp", "f", { arg msg; synth.set(\amp, msg[1]); });
  }

  free {
    synth.free;
  }
}
