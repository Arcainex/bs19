-- Infrequent survival needs. Times are real-world seconds.
Bodily = {
    enabled = true,
    reliefMinigame = false,
    funEnabled = true, -- F1 can override this for the whole server.
    fartCooldown = 8000,
    digestion = { foodFactor = 0.5, drinkFactor = 0.8, foodDelay = 120, drinkDelay = 45 },
    relief = { peeMs = 6000, poopMs = 9000 },
    pee = { minSeconds = 2 * 60 * 60, maxSeconds = 4 * 60 * 60, warningSeconds = 20 * 60, graceSeconds = 15 * 60 },
    poop = { minSeconds = 4 * 60 * 60, maxSeconds = 7 * 60 * 60, warningSeconds = 30 * 60, graceSeconds = 25 * 60 },
    soiledSeconds = 30 * 60,
    smellMultiplier = 1.65,
}
