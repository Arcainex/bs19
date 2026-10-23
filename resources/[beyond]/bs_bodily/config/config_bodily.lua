-- Infrequent survival needs. Times are real-world seconds.
Bodily = {
    enabled = true,
    pee = { minSeconds = 2 * 60 * 60, maxSeconds = 4 * 60 * 60, warningSeconds = 20 * 60, graceSeconds = 15 * 60 },
    poop = { minSeconds = 4 * 60 * 60, maxSeconds = 7 * 60 * 60, warningSeconds = 30 * 60, graceSeconds = 25 * 60 },
    soiledSeconds = 30 * 60,
    smellMultiplier = 1.65,
}
