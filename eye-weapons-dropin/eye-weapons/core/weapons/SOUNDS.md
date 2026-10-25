# Chimera — sound list

Every hook already exists in `chimera_behavior.gd` as `_sfx("name")`. Add the
`Sfx` autoload (`core/sfx.gd`), drop wavs in `res://assets/sfx/`, done.
Missing files are silent, never crashes — mix as you go.

| file | when it plays | what it should sound like | source idea |
|---|---|---|---|
| `scope_in.wav` | RMB pressed | short mechanical whirr-click, lens engaging (~0.25s) | Kenney UI/sci-fi pack, pitch down |
| `scope_out.wav` | RMB released | reverse-ish click, lens disengaging (~0.2s) | same pack |
| `pistol.wav` | hip tap | weak little pew — *negligible* on purpose (~0.15s) | OpenGameArt CC0 laser |
| `transform.wav` | hold crosses tap_window | CHUNK — drum swings in / coils engage (~0.3s). the mode-switch moment, make it felt | layered mechanical clunk + servo |
| `charge.wav` | while holding (loop) | rising hum, neutral enough to pitch-shift 0.7→1.6x (~1s loop, seamless) | synth hum, CC0 |
| `tier_ready.wav` | scoped charge hits mid | subtle tick/chime — "mid sniper ready" (~0.2s) | soft blip |
| `full_ready.wav` | scoped charge hits full | THE money sound — bright chime + shimmer (~0.5s). player should grin | chime + riser tail |
| `sniper_proj.wav` | scoped tap | supersonic crack, heavy (~0.4s) | rifle crack, CC0 |
| `sniper_hit.wav` | scoped mid release | deeper railgun thump (~0.5s) | layered boom + crack |
| `sniper_full.wav` | scoped full release | sniper_hit but *angrier* + shimmer tail (~0.7s) | sniper_hit + full_ready tail |
| `ricochet.wav` | each chain bounce | metallic zing dopplering away (~0.3s) | metal ping, pitch random |
| `grenade_launch.wav` | hip hold release | thunk-woosh, pitched by charge 0.9→1.2x (~0.4s) | thump + whoosh |
| `explosion.wav` | grenade detonates | (hook in projectile `_explode`) proper boom (~1s) | CC0 explosion |
| `dry.wav` | no ammo | dull click (~0.1s) | click |

**Where to get them (all free):** Kenney game assets (CC0, kenney.nl/assets —
grab the sci-fi/weapon/interface packs), OpenGameArt filtered to CC0
(hundreds of gunshots/explosions), or synthesize in 10 minutes with
[jsfxr](https://sfxr.me/) for the pews/blips and layer the big ones.

**Mixing rule of thumb:** pistol quiet (-6db), everything scoped loud,
`full_ready` the brightest thing in the mix. Mode switches should be *heard*
before they're seen.
