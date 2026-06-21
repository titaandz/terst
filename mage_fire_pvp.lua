-- ============================================================
--  Mage Fire - Routine PvP
--  Compatible NilName Unlocker API
--  Usage : charger via NilName > Scripts > Load File
-- ============================================================

local Routine = {}
Routine.__index = Routine

-- ── Utilitaires NilName ─────────────────────────────────────

local NN  = NilName          -- namespace principal de l'unlocker
local API = NN and NN.API    -- fonctions d'accès unitaire

local function Cast(spellName)
    if NN and NN.CastSpell then
        NN.CastSpell(spellName)
    else
        CastSpellByName(spellName)   -- fallback API standard
    end
end

local function SpellReady(spellName)
    local start, duration = GetSpellCooldown(spellName)
    if start == nil then return false end
    return (start == 0) or (GetTime() >= start + duration)
end

local function HasBuff(unit, buffName)
    local i = 1
    while true do
        local name = UnitBuff(unit, i)
        if not name then break end
        if name == buffName then return true end
        i = i + 1
    end
    return false
end

local function HasDebuff(unit, debuffName)
    local i = 1
    while true do
        local name = UnitDebuff(unit, i)
        if not name then break end
        if name == debuffName then return true end
        i = i + 1
    end
    return false
end

local function HealthPct(unit)
    local hp  = UnitHealth(unit)
    local max = UnitHealthMax(unit)
    if max == 0 then return 0 end
    return (hp / max) * 100
end

local function ManaPct()
    local m   = UnitMana("player")
    local max = UnitManaMax("player")
    if max == 0 then return 0 end
    return (m / max) * 100
end

local function InRange(unit)
    -- NilName expose souvent IsSpellInRange ou GetDistance
    if NN and NN.GetDistance then
        return NN.GetDistance(unit) <= 35
    end
    return IsSpellInRange("Fireball", unit) == 1
end

local function IsValidTarget()
    return UnitExists("target")
        and UnitCanAttack("player", "target")
        and not UnitIsDead("target")
        and InRange("target")
end

-- ── Spells Fire (noms génériques — adapter si le serveur
--   utilise des IDs spécifiques à Midnight) ─────────────────

local SPELLS = {
    Fireball        = "Fireball",
    Pyroblast       = "Pyroblast",
    FireBlast       = "Fire Blast",
    Scorch          = "Scorch",
    LivingBomb      = "Living Bomb",
    Combustion      = "Combustion",
    DragonBreath    = "Dragon's Breath",
    BlastWave       = "Blast Wave",
    IcyVeins        = "Icy Veins",         -- dispo si spec le permet
    IceBlock        = "Ice Block",
    Counterspell    = "Counterspell",
    Blink           = "Blink",
    MirrorImage     = "Mirror Image",
    FireballVolley  = "Flamestrike",
    Arcane          = "Arcane Explosion",
}

-- ── Rotation principale ─────────────────────────────────────

local function RotationFire()
    if not IsValidTarget() then return end

    local hp     = HealthPct("player")
    local target = "target"

    -- Défense : Ice Block si < 15 % HP
    if hp < 15 and SpellReady(SPELLS.IceBlock) then
        Cast(SPELLS.IceBlock)
        return
    end

    -- Blink si ciblé en mêlée (optionnel, dépend de ton setup)
    -- Cast(SPELLS.Blink)

    -- Interrupt : Counterspell si la cible est en train de caster
    if UnitCastingInfo and UnitCastingInfo(target) and SpellReady(SPELLS.Counterspell) then
        Cast(SPELLS.Counterspell)
        return
    end

    -- Burst : Combustion + Mirror Image si disponibles
    if SpellReady(SPELLS.Combustion) then
        Cast(SPELLS.Combustion)
    end
    if SpellReady(SPELLS.MirrorImage) then
        Cast(SPELLS.MirrorImage)
    end

    -- Living Bomb (DoT) si absent sur la cible
    if not HasDebuff(target, SPELLS.LivingBomb) and SpellReady(SPELLS.LivingBomb) then
        Cast(SPELLS.LivingBomb)
        return
    end

    -- Pyroblast si Hot Streak proc (buff "Hot Streak")
    if HasBuff("player", "Hot Streak") and SpellReady(SPELLS.Pyroblast) then
        Cast(SPELLS.Pyroblast)
        return
    end

    -- Fire Blast pour stacker Heating Up
    if SpellReady(SPELLS.FireBlast) then
        Cast(SPELLS.FireBlast)
        return
    end

    -- Scorch si en mouvement ou pour maintenir la vulnérabilité feu
    if SpellReady(SPELLS.Scorch) then
        Cast(SPELLS.Scorch)
        return
    end

    -- Fireball — sort de base
    Cast(SPELLS.Fireball)
end

-- ── Boucle principale (tick toutes les 100 ms) ─────────────

local ticker

local function StartRoutine()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(0.1, function()
        -- Ne rien faire si le joueur est en train de caster / mort
        if UnitIsDead("player") or UnitIsGhost("player") then return end
        RotationFire()
    end)
    print("[Routine] Mage Fire PvP — démarrée")
end

local function StopRoutine()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    print("[Routine] Mage Fire PvP — arrêtée")
end

-- ── Commandes slash ─────────────────────────────────────────

SLASH_MAGEFIRE1 = "/fire"
SlashCmdList["MAGEFIRE"] = function(msg)
    local cmd = msg:lower():match("^%s*(.-)%s*$")
    if cmd == "start" or cmd == "" then
        StartRoutine()
    elseif cmd == "stop" then
        StopRoutine()
    else
        print("Usage : /fire [start|stop]")
    end
end

-- ── Point d'entrée NilName (si l'unlocker charge le fichier) ─

if NN and NN.RegisterScript then
    NN.RegisterScript("MageFirePvP", {
        OnStart = StartRoutine,
        OnStop  = StopRoutine,
    })
end

print("[Routine] Mage Fire PvP chargée — /fire start | /fire stop")
