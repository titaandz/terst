-- ============================================================
--  Mage Fire Sunfury — Routine PvP
--  WoW Midnight 12.0.7
--  NilName Unlocker — API : Unlock() / NnBasic
-- ============================================================
--
--  Chargement : coller dans le panel NilName > Script
--  Commandes  : /fire start | /fire stop
--
-- ============================================================

-- ── NilName : wrapper Unlock() ──────────────────────────────
--
--  NilName expose les fonctions protégées via :
--    Unlock('FunctionName', arg1, arg2, ...)
--  ou directement si NnBasic les a déjà débloquées.

local function Cast(spellName, unit)
    unit = unit or "target"
    -- Essai via Unlock (méthode NilName recommandée)
    if Unlock then
        Unlock("CastSpellByName", spellName, unit)
    else
        CastSpellByName(spellName, unit)
    end
end

local function SpellReady(spellName)
    local start, duration = GetSpellCooldown(spellName)
    if not start then return false end
    return start == 0 or (GetTime() - start >= duration)
end

local function HasBuff(unit, name)
    local i = 1
    while true do
        local n = UnitBuff(unit, i)
        if not n then break end
        if n == name then return true end
        i = i + 1
    end
    return false
end

local function HasDebuff(unit, name)
    local i = 1
    while true do
        local n = UnitDebuff(unit, i)
        if not n then break end
        if n == name then return true end
        i = i + 1
    end
    return false
end

local function HealthPct(unit)
    local max = UnitHealthMax(unit)
    if max == 0 then return 0 end
    return UnitHealth(unit) / max * 100
end

local function IsCasting(unit)
    local spell = UnitCastingInfo(unit)
    if spell then return spell end
    return UnitChannelInfo(unit)
end

local function InRange(unit, spell)
    spell = spell or "Fireball"
    return IsSpellInRange(spell, unit) == 1
end

-- ── Spells & Buffs Midnight 12.0.7 ─────────────────────────

local S = {
    -- Fillers
    Fireball        = "Fireball",
    FrostfireBolt   = "Frostfire Bolt",   -- variante Frostfire build
    Scorch          = "Scorch",

    -- Procs / instants
    Pyroblast       = "Pyroblast",
    FireBlast       = "Fire Blast",
    Flamestrike     = "Flamestrike",

    -- Cooldowns offensifs
    Combustion      = "Combustion",
    MirrorImage     = "Mirror Image",

    -- Utilitaires / CC
    Polymorph       = "Polymorph",
    FrostNova       = "Frost Nova",
    Blink           = "Blink",
    Counterspell    = "Counterspell",
    SpellSteal      = "Spellsteal",

    -- Défensifs
    IceBlock        = "Ice Block",
    Cauterize       = "Cauterize",         -- talent cheat-death passif
    ShiftingPower   = "Shifting Power",    -- supprimé en Midnight, ignoré
}

local BUFFS = {
    HotStreak       = "Hot Streak",
    HeatingUp       = "Heating Up",
    Combustion      = "Combustion",
    FiredUp         = "Fired Up",          -- talent Apex : bonus dégâts feu
    Hyperthermia    = "Hyperthermia",      -- fenêtre post-Combustion (Sunfury)
    IceBlock        = "Ice Block",
}

-- ── Logique de rotation ─────────────────────────────────────

local function IsValidTarget()
    return UnitExists("target")
        and UnitCanAttack("player", "target")
        and not UnitIsDead("target")
        and InRange("target", S.Fireball)
end

local inCombustion = false

local function RotationFire()
    if not IsValidTarget() then return end
    if UnitIsDead("player") or UnitIsGhost("player") then return end

    local hp      = HealthPct("player")
    local tgt     = "target"
    local tgtHP   = HealthPct(tgt)
    local inComb  = HasBuff("player", BUFFS.Combustion)
    local hyper   = HasBuff("player", BUFFS.Hyperthermia)
    local hotStr  = HasBuff("player", BUFFS.HotStreak)
    local heatUp  = HasBuff("player", BUFFS.HeatingUp)

    -- ── Défensifs ────────────────────────────────────────────

    -- Ice Block si HP critique (< 10 %)
    if hp < 10 and SpellReady(S.IceBlock) and not HasBuff("player", BUFFS.IceBlock) then
        Cast(S.IceBlock, "player")
        return
    end

    -- Blink pour s'échapper du gap-close (à gérer avec une condition
    -- de distance si NilName expose NnObject:GetDistance)
    -- if NeedsBlink() and SpellReady(S.Blink) then Cast(S.Blink, "player") return end

    -- ── Interrupt ────────────────────────────────────────────

    if IsCasting(tgt) and SpellReady(S.Counterspell) then
        Cast(S.Counterspell)
        return
    end

    -- ── Spellsteal (buff précieux sur la cible) ──────────────
    -- (à activer manuellement ou avec une liste de buffs stealables)
    -- if SpellReady(S.SpellSteal) then Cast(S.SpellSteal) return end

    -- ── Burst : ouverture Combustion ─────────────────────────

    if SpellReady(S.Combustion) and SpellReady(S.MirrorImage) then
        Cast(S.MirrorImage, "player")
        Cast(S.Combustion, "player")
        return
    end

    -- ── Fenêtre Combustion / Hyperthermia ────────────────────
    --  Pendant Combustion tout crit → Fire Blast + Pyroblast en boucle.
    --  Hyperthermia (Sunfury) donne 6s de Pyroblast instants après Combustion.

    if inComb or hyper then
        if hotStr and SpellReady(S.Pyroblast) then
            Cast(S.Pyroblast)
            return
        end
        if SpellReady(S.FireBlast) then
            Cast(S.FireBlast)
            return
        end
        -- Pendant Combustion les fillers sont des Pyroblasts si Hot Streak
        Cast(S.Fireball)
        return
    end

    -- ── Hors Combustion : rotation soutenue ─────────────────

    -- Hot Streak proc → Pyroblast instant (ou Flamestrike si AoE)
    if hotStr then
        if SpellReady(S.Pyroblast) then
            Cast(S.Pyroblast)
            return
        end
    end

    -- Fire Blast : convertit Heating Up en Hot Streak (CD court)
    -- Utiliser uniquement si Heating Up est actif pour économiser les charges
    if heatUp and SpellReady(S.FireBlast) then
        Cast(S.FireBlast)
        return
    end

    -- Scorch sous 30 % HP cible (crit garanti en Midnight)
    if tgtHP < 30 and SpellReady(S.Scorch) then
        Cast(S.Scorch)
        return
    end

    -- Filler principal : Fireball (ou Frostfire Bolt si build Frostfire)
    Cast(S.Fireball)
end

-- ── CC utilitaire (appel manuel via /firepoly) ──────────────

local function CastPolymorph()
    if UnitExists("target") and SpellReady(S.Polymorph) then
        Cast(S.Polymorph)
    end
end

local function CastFrostNova()
    if SpellReady(S.FrostNova) then
        Unlock and Unlock("CastSpellByName", S.FrostNova) or CastSpellByName(S.FrostNova)
    end
end

-- ── Boucle principale ────────────────────────────────────────

local ticker

local function StartRoutine()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(0.1, RotationFire)
    print("|cff00ff00[MageFire]|r Routine démarrée — /fire stop pour arrêter")
end

local function StopRoutine()
    if ticker then ticker:Cancel(); ticker = nil end
    print("|cffff4400[MageFire]|r Routine arrêtée")
end

-- ── Commandes slash ──────────────────────────────────────────

SLASH_MAGEFIRE1 = "/fire"
SlashCmdList["MAGEFIRE"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(.-)%s*$")
    if cmd == "start" or cmd == "" then StartRoutine()
    elseif cmd == "stop"           then StopRoutine()
    elseif cmd == "poly"           then CastPolymorph()
    elseif cmd == "nova"           then CastFrostNova()
    else
        print("|cff00ccff[MageFire]|r Commandes : /fire start | stop | poly | nova")
    end
end

print("|cff00ccff[MageFire]|r Mage Fire PvP (Midnight 12.0.7) chargé — /fire start")
