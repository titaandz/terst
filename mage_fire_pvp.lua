-- ============================================================
--  Mage Fire Sunfury — Routine PvP Gladiateur
--  WoW Midnight 12.0.7  |  NilName Unlocker
-- ============================================================
--
--  /fire start | stop | poly | nova | burst
--
-- ============================================================

-- ════════════════════════════════════════════════════════════
--  1. PERFORMANCE : cache + throttle
-- ════════════════════════════════════════════════════════════
--
--  Toutes les valeurs coûteuses sont lues une seule fois par
--  tick dans une table STATE, jamais deux fois dans le même
--  tick. Les fonctions de rotation ne font que lire STATE.

local STATE       = {}   -- snapshot rafraîchi chaque tick
local TICK_RATE   = 0.05 -- 50 ms (~20 ticks/s) — bon compromis perf/réactivité

-- Throttle séparé pour les vérifications lentes (1 s)
local SLOW_RATE   = 1.0
local slowTimer   = 0

-- ════════════════════════════════════════════════════════════
--  2. WRAPPERS NILNAME
-- ════════════════════════════════════════════════════════════

local function Cast(spell, unit)
    if Unlock then
        Unlock("CastSpellByName", spell, unit or "target")
    else
        CastSpellByName(spell, unit or "target")
    end
end

local function StopCast()
    if Unlock then Unlock("SpellStopCasting")
    else SpellStopCasting() end
end

-- ════════════════════════════════════════════════════════════
--  3. HELPERS (opérations atomiques, pas de lecture dupliquée)
-- ════════════════════════════════════════════════════════════

local function SpellCD(spell)
    local s, d = GetSpellCooldown(spell)
    if not s then return 999 end
    if s == 0 then return 0 end
    return math.max(0, (s + d) - GetTime())
end

local function SpellReady(spell)  return SpellCD(spell) < 0.2 end

local function GetBuffRemain(unit, name)
    local i = 1
    while true do
        local n, _, _, _, _, exp = UnitBuff(unit, i)
        if not n then return 0 end
        if n == name then return exp and (exp - GetTime()) or 999 end
        i = i + 1
    end
end

local function HasBuff(unit, name) return GetBuffRemain(unit, name) > 0 end

local function HasDebuff(unit, name)
    local i = 1
    while true do
        local n = UnitDebuff(unit, i)
        if not n then return false end
        if n == name then return true end
        i = i + 1
    end
end

local function UnitHP(unit)
    local m = UnitHealthMax(unit)
    return m > 0 and (UnitHealth(unit) / m * 100) or 0
end

local function IsCasting(unit)
    local s = UnitCastingInfo(unit)
    if s then return s end
    return UnitChannelInfo(unit)
end

local function InMeleeRange(unit)
    return CheckInteractDistance(unit, 3)  -- ~5 yards
end

local function InSpellRange(unit)
    return IsSpellInRange("Fireball", unit) == 1
end

local function IsCC(unit)
    -- vérifie si l'unité est sous un CC (poly, nova, etc.)
    return HasDebuff(unit, "Polymorph")
        or HasDebuff(unit, "Frost Nova")
        or HasDebuff(unit, "Freezing Trap")
        or HasDebuff(unit, "Cyclone")
end

local function IsHealer(unit)
    -- Heuristique : classe à vocation heal + puissance de soin élevée
    local _, cls = UnitClass(unit)
    if not cls then return false end
    -- On peut affiner avec UnitGroupRolesAssigned si dispo
    if UnitGroupRolesAssigned then
        return UnitGroupRolesAssigned(unit) == "HEALER"
    end
    -- Fallback : classes pouvant heal
    return cls == "PRIEST" or cls == "DRUID" or cls == "PALADIN"
        or cls == "SHAMAN" or cls == "MONK" or cls == "EVOKER"
end

-- ════════════════════════════════════════════════════════════
--  4. SPELLS & BUFF NAMES — Midnight 12.0.7
-- ════════════════════════════════════════════════════════════

local S = {
    Fireball        = "Fireball",
    Pyroblast       = "Pyroblast",
    FireBlast       = "Fire Blast",
    Scorch          = "Scorch",
    DragonBreath    = "Dragon's Breath",
    Flamestrike     = "Flamestrike",

    Combustion      = "Combustion",
    MirrorImage     = "Mirror Image",

    Polymorph       = "Polymorph",
    FrostNova       = "Frost Nova",
    Counterspell    = "Counterspell",
    SpellSteal      = "Spellsteal",
    Blink           = "Blink",
    RingOfFrost     = "Ring of Frost",

    IceBlock        = "Ice Block",
}

local B = {
    HotStreak       = "Hot Streak",
    HeatingUp       = "Heating Up",
    Combustion      = "Combustion",
    Hyperthermia    = "Hyperthermia",   -- Sunfury : 6 s post-Combustion
    FiredUp         = "Fired Up",
    IceBlock        = "Ice Block",
    Polymorphed     = "Polymorph",
}

-- ════════════════════════════════════════════════════════════
--  5. SNAPSHOT STATE (appelé une fois par tick)
-- ════════════════════════════════════════════════════════════

local function UpdateState()
    -- Joueur
    STATE.hp            = UnitHP("player")
    STATE.inCombat      = UnitAffectingCombat("player")
    STATE.isCasting     = UnitCastingInfo("player") ~= nil
    STATE.mana          = UnitPower("player") / math.max(1, UnitPowerMax("player")) * 100

    -- Buffs joueur (lus une seule fois)
    STATE.hotStreak     = HasBuff("player", B.HotStreak)
    STATE.heatingUp     = HasBuff("player", B.HeatingUp)
    STATE.inCombustion  = HasBuff("player", B.Combustion)
    STATE.inHyper       = HasBuff("player", B.Hyperthermia)
    STATE.inIceBlock    = HasBuff("player", B.IceBlock)
    STATE.combustRemain = GetBuffRemain("player", B.Combustion)

    -- Cible principale
    STATE.hasTarget     = UnitExists("target") and UnitCanAttack("player","target") and not UnitIsDead("target")
    STATE.tgtHP         = STATE.hasTarget and UnitHP("target") or 0
    STATE.tgtInRange    = STATE.hasTarget and InSpellRange("target") or false
    STATE.tgtCasting    = STATE.hasTarget and IsCasting("target") or nil
    STATE.tgtIsCC       = STATE.hasTarget and IsCC("target") or false
    STATE.tgtIsHealer   = STATE.hasTarget and IsHealer("target") or false
    STATE.tgtInMelee    = STATE.hasTarget and InMeleeRange("target") or false

    -- focus (healer off-target habituel)
    STATE.hasFocus      = UnitExists("focus") and UnitCanAttack("player","focus") and not UnitIsDead("focus")
    STATE.focusIsHealer = STATE.hasFocus and IsHealer("focus") or false
    STATE.focusCasting  = STATE.hasFocus and IsCasting("focus") or nil
    STATE.focusInRange  = STATE.hasFocus and (IsSpellInRange("Counterspell","focus") == 1) or false

    -- Cooldowns (lus une seule fois)
    STATE.cdCombustion  = SpellCD(S.Combustion)
    STATE.cdFireBlast   = SpellCD(S.FireBlast)
    STATE.cdCS          = SpellCD(S.Counterspell)
    STATE.cdPoly        = SpellCD(S.Polymorph)
    STATE.cdNova        = SpellCD(S.FrostNova)
    STATE.cdDB          = SpellCD(S.DragonBreath)
    STATE.cdBlink       = SpellCD(S.Blink)
    STATE.cdIceBlock    = SpellCD(S.IceBlock)
    STATE.cdMirror      = SpellCD(S.MirrorImage)
    STATE.cdRoF         = SpellCD(S.RingOfFrost)
end

-- ════════════════════════════════════════════════════════════
--  6. FAKE CAST
-- ════════════════════════════════════════════════════════════
--
--  Principe gladiateur :
--   - On commence un Fireball (cast long) pour forcer le CS ennemi
--   - Dès que le CS part (détecté par debuff "Silenced" sur nous OU
--     par la disparition du cast ennemi suivant), on annule et on
--     caste librement pendant la fenêtre de DR
--
--  États de la state machine :
--    "idle"      : pas de fake en cours
--    "baiting"   : Fireball lancé comme leurre, on attend le CS
--    "free"      : CS ennemi consommé, fenêtre libre

local FAKE = {
    state       = "idle",
    baitStart   = 0,
    freeUntil   = 0,
    BAIT_WINDOW = 2.0,   -- durée max pendant laquelle on attend le CS ennemi
    FREE_WINDOW = 3.0,   -- fenêtre libre après CS consommé
}

local function FakeCastUpdate()
    local now = GetTime()

    if FAKE.state == "baiting" then
        local silenced = HasDebuff("player", "Silenced")
                      or HasDebuff("player", "Interrupted")
        if silenced then
            -- CS ennemi tombé sur notre fake → on annule et on est libre
            StopCast()
            FAKE.state     = "free"
            FAKE.freeUntil = now + FAKE.FREE_WINDOW
            return
        end
        -- Timeout du bait : CS n'est pas venu, on continue normalement
        if now - FAKE.baitStart > FAKE.BAIT_WINDOW then
            FAKE.state = "idle"
        end
    elseif FAKE.state == "free" then
        if now > FAKE.freeUntil then
            FAKE.state = "idle"
        end
    end
end

local function ShouldFakeCast()
    -- On lance un fake si :
    --  - ennemi peut interrompre (caster) et son CS est dispo
    --  - on n'est pas déjà en bait/free
    --  - Combustion arrive dans < 5 s (on veut préserver la fenêtre)
    if FAKE.state ~= "idle" then return false end
    if not STATE.hasTarget then return false end
    if STATE.cdCombustion > 5 then return false end
    -- Vérifier que la cible a un kick disponible (heuristique : caster actif)
    if STATE.tgtCasting then return false end  -- elle caste déjà, pas de kick dispo
    return true
end

local function StartFakeCast()
    Cast(S.Fireball)   -- on commence le cast...
    FAKE.state     = "baiting"
    FAKE.baitStart = GetTime()
    -- Le tick suivant détectera si on se fait interrompre
end

-- ════════════════════════════════════════════════════════════
--  7. GESTION DES CIBLES : target / focus / off-target poly
-- ════════════════════════════════════════════════════════════
--
--  Logique gladiateur :
--   1. Healer en focus → Polymorph dessus quand il caste un gros heal
--   2. Dragon's Breath sur le melee qui nous presse → Poly sur heal derrière
--   3. Combustion sur le DPS (kill target) isolé après CC sur heal

local function TryPolymorphHealer()
    -- Poly sur le focus healer s'il caste et que notre CS sur lui n'est pas utile
    if not STATE.hasFocus then return false end
    if not STATE.focusIsHealer then return false end
    if STATE.cdPoly > 0 then return false end
    if not STATE.focusCasting then return false end
    if not (IsSpellInRange(S.Polymorph, "focus") == 1) then return false end

    -- Ne pas poly si déjà CC
    if IsCC("focus") then return false end

    -- Switcher temporairement sur le focus pour poly
    -- NilName : TargetUnit est protégé, on utilise Unlock
    if Unlock then Unlock("TargetUnit", "focus") end
    Cast(S.Polymorph)
    -- Retour sur la target kill après le cast (géré à la prochaine itération)
    return true
end

local function TryDragonBreathPoly()
    -- DB sur le melee qui presse → Poly immédiate sur healer focus
    if not STATE.hasTarget then return false end
    if not STATE.tgtInMelee then return false end
    if STATE.cdDB > 0 then return false end
    if STATE.cdPoly > 0 then return false end

    Cast(S.DragonBreath)
    -- Enchaîner poly sur focus healer si possible
    if STATE.hasFocus and STATE.focusIsHealer then
        if Unlock then Unlock("TargetUnit", "focus") end
        Cast(S.Polymorph)
    end
    return true
end

local function TryCounterspell()
    -- Priorité 1 : CS sur focus healer qui caste un gros heal
    if STATE.hasFocus and STATE.focusCasting and STATE.focusInRange and STATE.cdCS < 0.2 then
        if Unlock then Unlock("TargetUnit", "focus") end
        Cast(S.Counterspell)
        return true
    end
    -- Priorité 2 : CS sur target qui caste
    if STATE.hasTarget and STATE.tgtCasting and STATE.tgtInRange and STATE.cdCS < 0.2 then
        Cast(S.Counterspell)
        return true
    end
    return false
end

-- ════════════════════════════════════════════════════════════
--  8. COOLDOWNS DÉFENSIFS
-- ════════════════════════════════════════════════════════════

local function HandleDefensive()
    -- Ice Block HP critique
    if STATE.hp < 10 and not STATE.inIceBlock and STATE.cdIceBlock < 0.2 then
        Cast(S.IceBlock, "player")
        return true
    end
    -- Blink si melee en mêlée et Blink dispo
    if STATE.tgtInMelee and STATE.cdBlink < 0.2 then
        if Unlock then Unlock("CastSpellByName", S.Blink) end
        return true
    end
    -- Frost Nova pour créer de la distance
    if STATE.tgtInMelee and STATE.cdBlink > 2 and STATE.cdNova < 0.2 then
        Cast(S.FrostNova, "player")
        return true
    end
    return false
end

-- ════════════════════════════════════════════════════════════
--  9. BURST WINDOW : Combustion + setup
-- ════════════════════════════════════════════════════════════
--
--  Setup gladiateur :
--   1. S'assurer que le healer est CC (Poly ou Nova)
--   2. MirrorImage → Combustion
--   3. FireBlast → Pyroblast loop
--   4. Pendant Hyperthermia (post-Combust) : Pyroblast spam

local function HandleBurstWindow()
    -- Pendant Combustion ou Hyperthermia
    if STATE.inCombustion or STATE.inHyper then
        -- Pyroblast si Hot Streak disponible
        if STATE.hotStreak and SpellReady(S.Pyroblast) then
            Cast(S.Pyroblast)
            return true
        end
        -- Fire Blast pour générer Hot Streak (toujours crit pendant Combustion)
        if STATE.cdFireBlast < 0.2 then
            Cast(S.FireBlast)
            return true
        end
        -- Scorch comme filler pendant Combustion (crit garanti)
        if SpellReady(S.Scorch) then
            Cast(S.Scorch)
            return true
        end
        return true
    end

    -- Setup Combustion : lancer si healer CC + Mirror Image ready
    local healerIsCC = not STATE.hasFocus
                    or (STATE.hasFocus and IsCC("focus"))
                    or not STATE.focusIsHealer

    if STATE.cdCombustion < 0.2 and healerIsCC then
        if STATE.cdMirror < 0.2 then
            Cast(S.MirrorImage, "player")
        end
        Cast(S.Combustion, "player")
        return true
    end

    return false
end

-- ════════════════════════════════════════════════════════════
--  10. ROTATION SOUTENUE (hors Combustion)
-- ════════════════════════════════════════════════════════════

local function HandleSustained()
    -- Hot Streak → Pyroblast instant
    if STATE.hotStreak and SpellReady(S.Pyroblast) then
        Cast(S.Pyroblast)
        return
    end

    -- Fire Blast pour convertir Heating Up en Hot Streak (ne pas gaspiller)
    if STATE.heatingUp and STATE.cdFireBlast < 0.2 then
        Cast(S.FireBlast)
        return
    end

    -- Scorch crit garanti sous 30 % HP cible
    if STATE.tgtHP < 30 and SpellReady(S.Scorch) then
        Cast(S.Scorch)
        return
    end

    -- Filler : Fireball
    Cast(S.Fireball)
end

-- ════════════════════════════════════════════════════════════
--  11. TICK PRINCIPAL
-- ════════════════════════════════════════════════════════════

local function OnTick()
    -- 1. Snapshot (une seule lecture de toutes les valeurs)
    UpdateState()

    -- 2. Sanity checks
    if STATE.inIceBlock then return end
    if UnitIsDead("player") or UnitIsGhost("player") then return end
    if not STATE.inCombat then return end

    -- 3. Machine à états fake cast
    FakeCastUpdate()

    -- 4. Défensifs (priorité absolue)
    if HandleDefensive() then return end

    -- 5. Interrupts & CC sur healers/focus (haute priorité)
    if TryCounterspell() then return end

    -- 6. Pas de cible valide → rien à faire
    if not STATE.hasTarget or not STATE.tgtInRange then return end

    -- 7. Ne pas interrompre un poly en cours sur la cible
    if STATE.tgtIsCC then
        -- Pendant que la target est CC → poly sur healer focus / fake cast
        if TryPolymorphHealer() then return end
        -- Fake cast pour baiter le CS ennemi avant Combustion
        if ShouldFakeCast() then StartFakeCast() return end
        return
    end

    -- 8. Dragon's Breath → poly si le melee nous colle
    if TryDragonBreathPoly() then return end

    -- 9. Poly sur healer focus (indépendamment du burst)
    if TryPolymorphHealer() then return end

    -- 10. Burst / Combustion window
    if HandleBurstWindow() then return end

    -- 11. Fake cast si fenêtre libre et Combust proche
    if FAKE.state == "free" then
        -- CS ennemi consommé → rotation libre sans interruption possible
        HandleSustained()
        return
    end

    if ShouldFakeCast() then
        StartFakeCast()
        return
    end

    -- 12. Rotation soutenue normale
    HandleSustained()
end

-- ════════════════════════════════════════════════════════════
--  12. BOUCLE & COMMANDES
-- ════════════════════════════════════════════════════════════

local ticker

local function StartRoutine()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(TICK_RATE, OnTick)
    print("|cff00ff00[MageFire]|r Routine gladiateur démarrée (/fire stop)")
end

local function StopRoutine()
    if ticker then ticker:Cancel(); ticker = nil end
    FAKE.state = "idle"
    print("|cffff4400[MageFire]|r Routine arrêtée")
end

SLASH_MAGEFIRE1 = "/fire"
SlashCmdList["MAGEFIRE"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(.-)%s*$")
    if     cmd == "start" or cmd == "" then StartRoutine()
    elseif cmd == "stop"               then StopRoutine()
    elseif cmd == "poly"               then TryPolymorphHealer()
    elseif cmd == "nova"               then Cast(S.FrostNova, "player")
    elseif cmd == "burst"              then HandleBurstWindow()
    elseif cmd == "fake"               then StartFakeCast()
    else
        print("|cff00ccff[MageFire]|r /fire start|stop|poly|nova|burst|fake")
    end
end

print("|cff00ccff[MageFire]|r Mage Fire PvP Gladiateur (Midnight 12.0.7) — /fire start")
