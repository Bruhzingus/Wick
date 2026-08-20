# SOUND DESIGN — UNLITTIUS

## Audio identity

Unlittius should sound like:
- stone under impossible tension;
- low cave resonance;
- mineral grinding;
- dry rock plates moving against one another;
- faint supernatural violet energy;
- ritual pressure rather than demonic screaming.

Avoid:
- obvious human voice lines;
- generic monster roaring every attack;
- metallic robot servos;
- huge orchestral spell sounds;
- bright magical sparkle spam.

The audio should make the player feel that the cave itself is moving.

---

# Mix architecture

Recommended groups:
```text
SoundService
├── Master
├── Ambience
├── Music
├── SFX
│   ├── EnemySFX
│   │   └── BossSFX
│   └── ImpactSFX
```

If the project already has SoundGroups, integrate into those rather than duplicating.

3D boss cues should normally originate from:
- `AudioEmitter` attachment on torso;
- specific hand / boulder attachments;
- impact locations for boulder/dripstone;
- chamber ceiling for banish sounds.

Recommended starting 3D attenuation:
- RollOffMode: `InverseTapered`
- close body sounds min distance: 8–12 studs
- big spell / chamber cues max distance: 55–80 studs
- melee / claw cues max distance: 30–45 studs

Tune to the chamber size.

---

# Persistent layers

## `Boss_Idle_StoneTension_Loop`
Very quiet.
- low 50–120 Hz stone resonance;
- irregular rock creak;
- occasional tiny grit fall;
- no obvious looping rhythm.

Volume should be low enough that players mainly notice it when near the dais.

## `Boss_Rune_Hum_Loop`
- subtle violet supernatural hum;
- almost inaudible when candles are mostly lit;
- strongest at 0 candles;
- fade volume with `power = 1 - candlesLit/8`.

---

# Dripstone cues

### `Dripstone_Charge`
Starts during arm raise.
Layers:
- deep ceiling groan;
- tiny grit falling;
- stone stress crack.

### `Dripstone_Snap`
At 1.62s.
- very dry, sharp rock crack;
- short low-frequency impact;
- magical pressure release.

### `Dripstone_Fall_*`
3–5 variations.
- air movement;
- tumbling rock;
- no cartoon whistle.

### `Dripstone_Impact_*`
4+ variations.
- heavy stone impact;
- cave reverb tail;
- gravel scatter.

---

# Boulder Burst cues

### `Boulder_Conjure`
- stone materializing / assembling;
- gravel pulling inward;
- low violet pulse.

### `Boulder_Fire`
2–3 variations.
- compressed air / magical push;
- heavy rock launch;
- not a gunshot.

### `Boulder_Flyby`
Optional loop attached to projectile:
- low rushing air;
- rolling stone resonance.

### `Boulder_Impact`
4+ variations:
- heavy blunt stone impact;
- debris;
- low cave tail.

The second shot should not use the exact same pitch/sample as the first.

---

# Summon Gnawers cues

### `Summon_Rise`
- rising cave resonance;
- reversed grit / rock draw;
- very soft ritual harmonic.

### `Summon_Open`
When arms reach high position.
- sub-bass bloom;
- stone ring resonance.

### `Gnawer_Spawn`
- ground crack;
- dirt/gravel burst;
- existing Gnawer audio can take over immediately.

No chanting human voice is required.

---

# Melee cues

### `Melee_Windup`
- claws scraping against each other / stone cuff;
- short inhale-like pressure sound, but non-vocal.

### `Melee_Swipe_*`
At least 3 variations.
- fast heavy air shear;
- rock blade scrape.

### `Melee_Hit_Player`
- blunt + sharp stone impact;
- mix under player damage feedback.

### `Melee_Hit_World`
- claw scrape against stone floor / dais.

---

# Candle recoil cues

This needs to be extremely recognizable.

### `Candle_Recoil_Impact`
Layers:
- violent brittle stone crack;
- low magical suppression thump;
- short violet energy collapse.

### `Rune_Dim`
- low electrical/mineral fade;
- short resonant descending tone.

Every candle uses subtle variation so eight repetitions do not become irritating.

---

# Banish cues

### Phase 1: `Banish_Unbind`
- rune destabilization;
- orbit stones vibrating;
- rising sub tone.

### Phase 2: `Banish_Rise`
- heavy stone dragged upward;
- increasing cave resonance.

### Phase 3: `Banish_Ceiling_Embed`
- long stone scrape;
- heavy ceiling impact;
- large dust burst.

### Phase 4: `Banish_Seal`
- rock crack lines closing;
- final deep thud;
- supernatural hum disappears.

Then leave **intentional silence** for a short moment before normal chamber ambience dominates.

---

# Variation rules

Any cue played frequently:
- at least 3 variations where possible;
- PlaybackSpeed randomization only ±2–4%;
- avoid obvious chipmunk pitch changes;
- randomize volume ±5%;
- never restart the exact same loop phase for every attack.

---

# Candle-based mix progression

At 0 candles:
- rune hum 100%;
- stone tension 100%;
- purple attack accents strongest.

At 4 candles:
- rune hum ~60%;
- stone tension ~85%;
- candle ambience more dominant.

At 7 candles:
- rune hum ~20%;
- boss supernatural layer weak;
- warm room sound dominates.

At banish:
- supernatural layer resolves to zero.
