BeyondSurvival - custom audio
=============================

Drop .ogg, .mp3 or .wav files in THIS folder, then name them in a config.

Zombie voices:  bs_zombies/config/config_zombies.lua
                -> Zombies.Sounds  (ambient growls, per ped model)
                -> Zombies.Cues    (alerted / attack / death)

  files = { 'zombie_idle_01.ogg', 'zombie_idle_02.ogg' }

One is picked at random each time, and `pitch` varies the playback rate, so
three files do not sound like three files.

After adding files:  restart bs_ui  then  restart bs_zombies
No manifest edit is needed - the glob already covers this folder.

To prove a file is present and audible, on its own, before anything else has
to be working:

  /soundtest zombie_idle_01.ogg

If you hear nothing, F8 will say why (missing file, bad decode, etc).

WHY NOT THE .awc PACK: the "Sounds for Simple Zombies" download is an OpenIV
.oiv that REPLACES vanilla wave containers. Streaming a replacement for a bank
that lives inside the game's own RPF does not reliably take in FiveM, which is
why the voices never changed. Ordinary audio files played through here are the
route that works.
