fx_version 'cerulean'
game 'gta5'

author 'Nutria'
description 'crawl_steps - a custom crawl clip dictionary donated to BeyondSurvival by Nutria. Streaming only: this resource contains no script of any kind, just the one .ycd. It provides the anim dictionary `crawl_steps`, holding `crawl_loop`, `crawl_step_01`..`crawl_step_22` and `crawl_turn_01`..`crawl_turn_22`. bs_zombies uses it for the crawler zombie locomotion; see CREDITS.md for attribution and for why there is no PATCHES.md.'
version '1.0.0'

-- No scripts or dependencies on purpose: streaming-only resource.
-- The dict name comes from the .ycd filename (crawl_steps). Renaming the file breaks RequestAnimDict calls in bs_zombies.
