// Engine_Lagarta
// Ciat-Lonbarde synthesis for norns
//
// Three interacting sections:
//   QUANTUSSY - 5 cross-modulated bounds oscillators in a ring
//   CLICKER   - dual impulse voices with ring modulation
//   GONGS     - resonant bodies excited by clicks
//
// Inspired by Peter Blasser's paper circuits:
//   bounds oscillators, banana jack patching,
//   chaotic cross-modulation, and the philosophy
//   that narrowing bounds raises pitch AND lowers amplitude

Engine_Lagarta : CroneEngine {
  var synth;

  *new { arg context, doneCallback;
    ^super.new(context, doneCallback);
  }

  alloc {
    SynthDef(\lagarta, {
      arg out=0, amp=0.5,
        // quantussy ring
        q_freq1=55, q_freq2=82, q_freq3=131, q_freq4=196, q_freq5=330,
        q_bounds=0.5, q_cross=0.3, q_mix=0.5, q_fold=0.5,
        // clicker
        click_rate=3, click_decay=0.008, click_pitch=800,
        click_ring=0.5, click_amp=0.5, click_free=1,
        t_click=0, // trigger arg (auto-resets)
        // gongs
        gong1=400, gong2=633, gong3=1048, gong4=1672,
        gong_decay=1.5, gong_amp=0.3,
        // global
        chaos=0.3, drift=0.1;

      var fb, q1, q2, q3, q4, q5, quantussy;
      var int_trig, ext_trig, dust_trig, trig;
      var click_env, click1, click2, clicker;
      var gong_in, gongs;
      var sig;

      // ---- QUANTUSSY RING ----
      // 5 oscillators in a feedback ring
      // each modulates the next's frequency via cross-mod
      // VarSaw models the triangle-core bounds oscillator
      // variable width = the analog wobble of real CL capacitors

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

      // close the ring: osc5 feeds back to osc1
      LocalOut.ar([q5]);

      // mix and fold
      // Fold.ar simulates signal bouncing off bounds
      // as bounds narrow, signal folds more = more harmonics + lower amplitude
      // this IS the CL bounds behavior
      quantussy = Mix([q1, q2, q3, q4, q5]) * 0.2;
      quantussy = Fold.ar(quantussy * (1 + (q_fold * 4)), q_bounds.neg, q_bounds);
      quantussy = quantussy * q_mix;

      // ---- CLICKER ----
      // "an orchestra in a microsecond"
      // dual impulse voices: very short AD envelopes
      // ring modulation between voices creates sum/difference tones
      // golden ratio frequency relationship between voices

      int_trig = Impulse.ar(
        click_rate + (Crackle.ar(1.5 + (chaos * 0.5)) * chaos * click_rate * 0.4)
      ) * click_free;
      ext_trig = Trig1.ar(K2A.ar(t_click), SampleDur.ir);
      dust_trig = Dust.ar(chaos * 8);
      trig = int_trig + ext_trig + dust_trig;

      click_env = EnvGen.ar(Env.perc(0.00005, click_decay), trig);

      // voice 1: base pitch, modulated by quantussy chaos
      click1 = click_env * SinOsc.ar(
        (click_pitch + (quantussy * 200 * chaos)).max(20)
      );
      // voice 2: golden ratio above, different chaos modulation
      click2 = click_env * SinOsc.ar(
        (click_pitch * 1.618 + (quantussy * 300 * chaos)).max(20)
      );

      // ring mod blend: 0 = voice 1 only, 1 = full ring mod
      clicker = ((click1 * click2 * click_ring) + (click1 * (1 - click_ring))) * click_amp * 3;

      // ---- GONGS ----
      // resonant bodies excited by clicker impulses
      // like Plumbutter's gong translators
      // inharmonic frequency ratios create bell/gamelan character
      // each gong decays at a different rate for spectral evolution

      gong_in = clicker + (dust_trig * 0.2);
      gongs = Mix([
        Ringz.ar(gong_in, gong1 + (LFNoise2.kr(0.1) * drift * 20), gong_decay),
        Ringz.ar(gong_in, gong2 + (LFNoise2.kr(0.13) * drift * 30), gong_decay * 0.75),
        Ringz.ar(gong_in, gong3 + (LFNoise2.kr(0.17) * drift * 40), gong_decay * 0.5),
        Ringz.ar(gong_in, gong4 + (LFNoise2.kr(0.19) * drift * 50), gong_decay * 0.3)
      ]) * 0.12 * gong_amp;

      // ---- MIX + OUTPUT ----
      sig = quantussy + clicker + gongs;
      sig = LeakDC.ar(sig);
      sig = sig.tanh; // soft saturation
      sig = sig * amp;

      // gentle stereo drift
      Out.ar(out, Pan2.ar(sig,
        LFNoise2.kr(0.1 + (chaos * 0.5)).range(-0.3, 0.3)
      ));
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

    // global
    this.addCommand("chaos", "f", { arg msg; synth.set(\chaos, msg[1]); });
    this.addCommand("drift", "f", { arg msg; synth.set(\drift, msg[1]); });
    this.addCommand("amp", "f", { arg msg; synth.set(\amp, msg[1]); });
  }

  free {
    synth.free;
  }
}
