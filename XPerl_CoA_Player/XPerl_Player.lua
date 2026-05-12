-- X-Perl UnitFrames
-- Author: Zek <Boodhoof-EU>
-- License: GNU GPL v3, 29 June 2007 (see LICENSE.txt)

local XPerl_Player_Events = {}
local isOutOfControl = nil
local playerClass, playerName
local conf, pconf
XPerl_RequestConfig(function(new) conf = new pconf = conf.player if (XPerl_Player) then XPerl_Player.conf = conf.player end end, "$Revision: 363 $")
local perc1F = "%.1f"..PERCENT_SYMBOL
local percD = "%d"..PERCENT_SYMBOL

local format = format
local GetNumRaidMembers = GetNumRaidMembers
local UnitIsDead = UnitIsDead
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsGhost = UnitIsGhost
local UnitIsAFK = UnitIsAFK
local UnitMana = UnitMana
local UnitManaMax = UnitManaMax
local UnitName = UnitName
local UnitPower = UnitPower
local UnitPowerType = UnitPowerType
local XPerl_SetHealthBar = XPerl_SetHealthBar

local XPerl_Player_InitDK
local XPerl_Player_InitAuraPips
local XPerl_Player_SetupAuraPips
local XPerl_Player_UpdateAuraPips
local XPerl_Player_UpdateCoAResourceBar
local XPerl_Player_EnsureAuraWidget

local XPerl_PlayerStatus_OnUpdate
local XPerl_Player_HighlightCallback

----------------------
-- Loading Function --
----------------------
function XPerl_Player_OnLoad(self)
	XPerl_SetChildMembers(self)
	self.partyid = "player"

	XPerl_BlizzFrameDisable(PlayerFrame)

	CombatFeedback_Initialize(self, self.hitIndicator.text, 30)

	XPerl_SecureUnitButton_OnLoad(self, "player", nil, PlayerFrameDropDown, PlayerFrame.menu)
	XPerl_SecureUnitButton_OnLoad(self.nameFrame, "player", nil, PlayerFrameDropDown, PlayerFrame.menu)

	self:RegisterEvent("VARIABLES_LOADED")

	self.EnergyLast = 0
	self.tutorialPage = 2
	self:SetScript("OnUpdate", XPerl_Player_OnUpdate)
	self:SetScript("OnEvent", XPerl_Player_OnEvent)
	self:SetScript("OnShow", XPerl_Unit_UpdatePortrait)
	self.time = 0

	self.nameFrame.pvp:SetScript("OnUpdate",
		function(self, elapsed)
			if (IsPVPTimerRunning()) then
				local timeLeft = GetPVPTimer()
				if (timeLeft > 0 and timeLeft < 300000) then		-- 5 * 60 * 1000
					timeLeft = floor(timeLeft / 1000)
					self.timer:Show()
					self.timer:SetFormattedText("%d:%02d", timeLeft / 60, timeLeft % 60)
					return
				end
			end
			self.timer:Hide()
		end)

	XPerl_Player_InitDK(self)
	XPerl_Player_InitAuraPips(self)
	if (self.runes and self.runes.resourceType == "auraPips") then
		XPerl_Player_SetupAuraPips(self)
	else
		XPerl_Player_SetupDK(self)
	end

	XPerl_RegisterHighlight(self.highlight, 3)
	XPerl_RegisterPerlFrames(self, {self.nameFrame, self.statsFrame, self.levelFrame, self.portraitFrame, self.groupFrame, self.runes})

	self.FlashFrames = {self.portraitFrame, self.nameFrame,
				self.levelFrame, self.statsFrame, self.runes}

	XPerl_RegisterOptionChanger(XPerl_Player_Set_Bits, self)
	XPerl_Highlight:Register(XPerl_Player_HighlightCallback, self)
	--self.IgnoreHighlightStates = {AGGRO = true}

	if (XPerlDB) then
		self.conf = XPerlDB.player
	end

	XPerl_Player_OnLoad = nil
end

-- XPerl_Player_HighlightCallback(updateName)
function XPerl_Player_HighlightCallback(self, updateGUID)
	if (updateGUID == UnitGUID("player")) then
		XPerl_Highlight:SetHighlight(self, updateGUID)
	end
end

-- UpdateAssignedRoles
local function UpdateAssignedRoles(self)
	local unit = self.partyid
	local icon = self.nameFrame.roleIcon
	local isTank, isHealer, isDamage
	local isInstance = select(2, IsInInstance())
	if (select(2, IsInInstance()) == "party") then
		-- No point getting it otherwise, as they can be wrong. Usually the values you had
		-- from previous instance if you're running more than one with the same people
		isTank, isHealer, isDamage = UnitGroupRolesAssigned("player")
	end

	if isTank then
		icon:SetTexture("Interface\\GroupFrame\\UI-Group-MainTankIcon")
		icon:Show()
	elseif isHealer then
		icon:SetTexture("Interface\\AddOns\\XPerl_CoA\\Images\\XPerl_RoleHealer")
		icon:Show()
	elseif isDamage then
		icon:SetTexture("Interface\\GroupFrame\\UI-Group-MainAssistIcon")
		icon:Show()
	else
		icon:Hide()
	end
end

-------------------------
-- The Update Function --
-------------------------

local function XPerl_Player_CombatFlash(self, elapsed, argNew, argGreen)
	if (XPerl_CombatFlashSet(self, elapsed, argNew, argGreen)) then
		XPerl_CombatFlashSetFrames(self)
	end
end

-- XPerl_Player_UpdateManaType
local function XPerl_Player_UpdateManaType(self)
	XPerl_SetManaBarType(self)
end

local secondaryPowerColours = {
	[0] = "mana",
	[1] = "rage",
	[2] = "focus",
	[3] = "energy",
	[6] = "runic_power",
}

local function XPerl_Player_ReadPower(unit, powerType)
	if (powerType == 0) then
		return UnitPower(unit, 0) or UnitMana(unit), UnitPowerMax(unit, 0) or UnitManaMax(unit)
	end

	return UnitPower(unit, powerType) or 0, UnitPowerMax(unit, powerType) or 0
end

local XPerl_Player_GetAuraResourceDefinition

local function XPerl_Player_GetAlternateResource(self)
	local definition = XPerl_Player_GetAuraResourceDefinition(self)
	local auraValue, auraMax, auraToken, auraColour = XPerl_GetAuraBarInfo(self.partyid, definition)
	if (auraValue ~= nil and auraMax ~= nil) then
		return "aura", auraValue, auraMax, auraToken, auraColour
	end

	local powerType, powerToken, powerColour = XPerl_GetAlternatePowerInfo(self.partyid)
	if (powerType ~= nil) then
		return "power", powerType, powerToken, powerColour
	end

	local currentValue, maxValue, resourceToken, resourceColour = XPerl_GetAuraResourceInfo(self.partyid, definition)
	if (currentValue ~= nil and maxValue ~= nil) then
		return "aura", currentValue, maxValue, resourceToken, resourceColour
	end
end

XPerl_Player_GetAuraResourceDefinition = function(self)
	local definition
	local class
	if (self.detectedAuraResourceClass) then
		definition = XPerl_GetClassAuraResourceDefinition(self.detectedAuraResourceClass)
		if (definition) then
			return definition
		end
	end

	definition, class = XPerl_FindAuraResourceDefinitionByAura(self.partyid)
	if (definition and class) then
		self.detectedAuraResourceClass = class
		return definition
	end

	class = XPerl_GetUnitClassToken(self.partyid)
	definition = XPerl_GetClassAuraResourceDefinition(class)
	if (definition) then
		self.detectedAuraResourceClass = class
		return definition
	end
end

local function XPerl_Player_UsesAuraWidget(self)
	local definition = XPerl_Player_GetAuraResourceDefinition(self)
	return definition and self.partyid == "player" and (definition.display == "pips" or definition.display == "badge")
end

local function XPerl_Player_UsesAuraPips(self)
	local definition = XPerl_Player_GetAuraResourceDefinition(self)
	return definition and definition.display == "pips" and self.partyid == "player"
end

local function XPerl_Player_ShouldHideCoAResourceBar(self)
	local definition = XPerl_Player_GetAuraResourceDefinition(self)
	return definition and self.partyid == "player" and ((definition.display == "pips" or definition.display == "badge") or definition.barAuras)
end

local function XPerl_Player_ShouldShowAlternateMana(self)
	local definition = XPerl_Player_GetAuraResourceDefinition(self)
	if (definition and definition.display and definition.barAuras) then
		return XPerl_Player_GetAlternateResource(self) ~= nil
	end

	if (XPerl_Player_UsesAuraWidget(self)) then
		return false
	end

	return XPerl_Player_GetAlternateResource(self) ~= nil
end

local function XPerl_Player_FormatAuraBadgeValue(definition, currentValue)
	local textMode = definition.badgeTextMode or "count"
	if (textMode == "percent") then
		local perStack = definition.badgeValuePerStack or 1
		return format("+%d%s", floor((currentValue or 0) * perStack + 0.5), definition.badgeSuffix or "")
	end

	return tostring(floor((currentValue or 0) + 0.5))
end

local function XPerl_Player_EnsureAuraWidget(self)
	if (self.runes or not XPerl_Player_UsesAuraWidget(self)) then
		return
	end

	XPerl_Player_InitAuraPips(self)
	if (self.runes and self.runes.resourceType == "auraPips") then
		XPerl_Player_SetupAuraPips(self)
	end
end

local function XPerl_Player_AuraPips_OnUpdate(self)
	local pulse = 0.45 + 0.35 * ((sin(GetTime() * 4) + 1) / 2)

	for _, pip in ipairs(self.list) do
		if (pip.badgeCountdown and pip.badgeEndTime) then
			local remaining = max(0, pip.badgeEndTime - GetTime())
			if (remaining > 0) then
				local countdown = ceil(remaining)
				local hurryThreshold = pip.badgeHurryThreshold or 3
				local isHurry = countdown <= hurryThreshold
				pip.badgePulse = isHurry
				pip.badgeCount:SetText(tostring(countdown))
				pip.badgeText:SetText(isHurry and (pip.badgeHurryText or "HURRY UP!") or (pip.badgeLabel or ""))
			else
				pip.badgeEndTime = nil
				pip.badgePulse = nil
			end
		end

		if (pip.badgeGlow and pip.badgePulse) then
			pip.badgeGlow:SetAlpha(pulse)
		elseif (pip.badgeGlow) then
			pip.badgeGlow:SetAlpha(pip.badgeGlowBaseAlpha or 0.18)
		end
		if (pip.pending) then
			for _, fragment in ipairs(pip.fragments) do
				if (fragment:IsShown()) then
					fragment:SetAlpha(pulse)
				end
			end
		elseif (pip.fill:IsShown()) then
			pip.fill:SetAlpha(1)
		end
	end
end

local function XPerl_Player_UpdateAuraPips(self)
	XPerl_Player_EnsureAuraWidget(self)

	local frame = self.runes
	if (not frame or frame.resourceType ~= "auraPips") then
		return
	end

	local definition = XPerl_Player_GetAuraResourceDefinition(self)
	if (not definition or (definition.display ~= "pips" and definition.display ~= "badge")) then
		frame:Hide()
		return
	end

	if (pconf and not pconf.showRunes) then
		frame:Hide()
		frame:SetScript("OnUpdate", nil)
		return
	end

	if (definition.display == "badge") then
		local currentValue, _, _, _, _, duration, endTime = XPerl_GetAuraResourceInfo(self.partyid, definition)
		if (currentValue == nil and not definition.showWhenEmpty) then
			frame:Hide()
			frame:SetScript("OnUpdate", nil)
			return
		end

		currentValue = currentValue or 0
		local pip = frame.list[1]
		local fillColour = definition.fillColour or {r = 0.95, g = 0.76, b = 0.24}
		local pendingColour = definition.pendingColour or fillColour
		local hasAura = currentValue > 0
		local countdown = hasAura and endTime and ceil(max(0, endTime - GetTime())) or nil
		local hurryThreshold = definition.badgeHurryThreshold or 3
		local isHurry = countdown and countdown <= hurryThreshold
		local modifierValue = definition.modifierAuras and XPerl_GetAuraValueInfo(self.partyid, definition.modifierAuras)
		local modifierText
		if (modifierValue) then
			if (definition.badgeModifierMode == "percent") then
				modifierText = format("+%d%%", floor(modifierValue * (definition.badgeModifierPerStack or 1) + 0.5))
			else
				modifierText = tostring(floor(modifierValue + 0.5))
			end
		end

		if (pip and pip.badgeText) then
			pip.base:SetVertexColor(0.28, 0.22, 0.1)
			pip.base:SetAlpha(0.14)
			pip.fill:SetVertexColor(fillColour.r, fillColour.g, fillColour.b)
			pip.fill:SetAlpha(hasAura and 0.85 or 0)
			pip.badgeGlow:SetVertexColor(pendingColour.r, pendingColour.g, pendingColour.b)
			pip.badgeGlowBaseAlpha = hasAura and 0.75 or 0.18
			pip.badgeGlow:SetAlpha(pip.badgeGlowBaseAlpha)
			pip.badgePulse = hasAura and isHurry
			pip.badgeCountdown = definition.badgeCountdown
			pip.badgeEndTime = endTime
			pip.badgeHurryThreshold = hurryThreshold
			pip.badgeHurryText = definition.badgeHurryText
			pip.badgeLabel = modifierText or definition.badgeLabel or XPerl_Player_FormatAuraBadgeValue(definition, currentValue)
			pip.crossH:SetVertexColor(fillColour.r, fillColour.g, fillColour.b)
			pip.crossV:SetVertexColor(fillColour.r, fillColour.g, fillColour.b)
			pip.badgeText:SetText(isHurry and (definition.badgeHurryText or "HURRY UP!") or (modifierText or definition.badgeLabel or XPerl_Player_FormatAuraBadgeValue(definition, currentValue)))
			pip.badgeText:SetTextColor(fillColour.r, fillColour.g, fillColour.b)
			if (definition.badgeCountdown) then
				pip.badgeCount:SetFontObject(GameFontNormalLarge)
			else
				pip.badgeCount:SetFontObject(GameFontHighlightSmall)
			end
			pip.badgeCount:SetText(hasAura and tostring(countdown or floor(currentValue + 0.5)) or "0")
			pip.badgeCount:SetTextColor(fillColour.r, fillColour.g, fillColour.b)
		end

		frame:Show()
		frame:SetScript("OnUpdate", XPerl_Player_AuraPips_OnUpdate)
		return
	end

	local currentValue, maxValue = XPerl_GetAuraResourceInfo(self.partyid, definition)
	currentValue = currentValue or 0
	maxValue = maxValue or definition.max or #frame.list
	local segmentCount = definition.segments or 3
	if (segmentCount < 1) then
		segmentCount = 1
	end
	local hasInfusion = XPerl_UnitHasAuraBySpellID(self.partyid, definition.infusionSpellID, "HELPFUL") ~= nil
	local fillColour = definition.fillColour or {r = 0.3, g = 0.8, b = 1}
	local pendingColour = definition.pendingColour or fillColour
	local wholeSouls = floor(currentValue + 0.0001)
	local fragmentValue = max(0, currentValue - wholeSouls)
	local pendingFragments = segmentCount > 1 and min(segmentCount, floor(fragmentValue * segmentCount + 0.0001)) or 0
	local activePending = false

	for index, pip in ipairs(frame.list) do
		local isFilled = index <= wholeSouls
		local isPending = index == (wholeSouls + 1) and index <= maxValue and pendingFragments > 0
		pip.pending = isPending

		pip.base:SetVertexColor(0.14, 0.2, 0.28)
		pip.base:SetAlpha(isFilled and 0.28 or 0.08)

		if (isFilled) then
			pip.fill:Show()
			if (hasInfusion) then
				pip.fill:SetVertexColor(0.78, 0.6, 1)
			else
				pip.fill:SetVertexColor(fillColour.r, fillColour.g, fillColour.b)
			end
			pip.fill:SetAlpha(1)
		elseif (isPending) then
			pip.fill:Hide()
			activePending = true
		else
			pip.fill:Hide()
		end

		for fragmentIndex, fragment in ipairs(pip.fragments) do
			local fragmentBack = pip.fragmentBacks and pip.fragmentBacks[fragmentIndex]
			if (fragmentBack) then
				if (not isFilled) then
					fragmentBack:Show()
					fragmentBack:SetVertexColor(0.24, 0.3, 0.38)
					fragmentBack:SetAlpha(isPending and 0.45 or 0.28)
				else
					fragmentBack:Hide()
				end
			end

			if (isPending and fragmentIndex <= pendingFragments) then
				fragment:Show()
				fragment:SetVertexColor(pendingColour.r, pendingColour.g, pendingColour.b)
				fragment:SetAlpha(1)
			else
				fragment:Hide()
			end
		end
	end

	frame:Show()
	frame:SetScript("OnUpdate", activePending and XPerl_Player_AuraPips_OnUpdate or nil)
end

function XPerl_Player_UpdateCoAResourceBar(self)
	local shouldHide = XPerl_Player_ShouldHideCoAResourceBar(self)
	local classToken = self.partyid and XPerl_GetUnitClassToken(self.partyid) or nil
	local allowMultiCastFrame = self.partyid == "player" and classToken == "NECROMANCER"
	for _, frame in ipairs({CoAResourceSegmentBar, CoAResourceBar, CoAResourceOrb, CoAMultiCastActionBarFrame}) do
		if (frame) then
			if (not frame.xperlHideHooked) then
				frame.xperlHideHooked = true
				frame:HookScript("OnShow", function(this)
					local ownerClass = XPerl_Player and XPerl_Player.partyid and XPerl_GetUnitClassToken(XPerl_Player.partyid) or nil
					local ownerAllowsMultiCast = XPerl_Player and XPerl_Player.partyid == "player" and ownerClass == "NECROMANCER"
					if (XPerl_Player and XPerl_Player_ShouldHideCoAResourceBar(XPerl_Player) and not (ownerAllowsMultiCast and this == CoAMultiCastActionBarFrame)) then
						if (this.EnableMouse) then
							this:EnableMouse(false)
						end
						this:SetAlpha(0)
						this:Hide()
					end
				end)
			end

			if (shouldHide and not (allowMultiCastFrame and frame == CoAMultiCastActionBarFrame)) then
				if (frame.EnableMouse) then
					frame:EnableMouse(false)
				end
				frame:SetAlpha(0)
				frame:Hide()
			else
				if (frame.EnableMouse) then
					frame:EnableMouse(true)
				end
				frame:SetAlpha(1)
			end
		end
	end
end

-- XPerl_Player_UpdateLeader()
function XPerl_Player_UpdateLeader(self)
	local nf = self.nameFrame

	-- Loot Master
	local method, index
	if (UnitInParty("party1") or UnitInRaid("player")) then
		method, index = GetLootMethod()
	end
	if (method == "master" and index == 0) then
		nf.masterIcon:Show()
	else
		nf.masterIcon:Hide()
	end

	-- Leader
	if (IsPartyLeader()) then
		nf.leaderIcon:Show()
	else
		nf.leaderIcon:Hide()
	end

	UpdateAssignedRoles(self)

	if (pconf and pconf.partyNumber and GetNumRaidMembers() > 0) then
		for i = 1,GetNumRaidMembers() do
			local name, rank, subgroup = GetRaidRosterInfo(i)
			if (UnitIsUnit("raid"..i, "player")) then
				if (pconf.withName) then
					nf.group:SetFormattedText(XPERL_RAID_GROUPSHORT, subgroup)
					nf.group:Show()
					self.groupFrame:Hide()
					return
				else
					self.groupFrame.text:SetFormattedText(XPERL_RAID_GROUP, subgroup)
					self.groupFrame:Show()
					nf.group:Hide()
					return
				end
			end
		end
	end

	nf.group:Hide()
	self.groupFrame:Hide()
end

-- XPerl_Player_UpdateCombat
local function XPerl_Player_UpdateCombat(self)
	local nf = self.nameFrame
	if (UnitAffectingCombat(self.partyid)) then
		nf.text:SetTextColor(1,0,0)
		nf.combatIcon:SetTexCoord(0.5, 1.0, 0.0, 0.5)
		nf.combatIcon:Show()
	else
		if (self.partyid ~= "player") then
			local c = conf.colour.reaction.none
			nf.text:SetTextColor(c.r, c.g, c.b, conf.transparency.text)
		else
			XPerl_ColourFriendlyUnit(nf.text, self.partyid)
		end

		if (IsResting()) then
			nf.combatIcon:SetTexCoord(0, 0.5, 0.0, 0.5)
			nf.combatIcon:Show()
		else
			nf.combatIcon:Hide()
		end
	end
end

-- XPerl_Player_UpdateName()
local function XPerl_Player_UpdateName(self)
	playerName = UnitName(self.partyid)
	self.nameFrame.text:SetText(playerName)
	XPerl_Player_UpdateCombat(self)
end

-- XPerl_Player_UpdateClass
local function XPerl_Player_UpdateClass(self)
	playerClass = select(2, UnitClass(self.partyid))
	playerName = UnitName(self.partyid)
	local l, r, t, b = XPerl_ClassPos(playerClass)
	self.classFrame.tex:SetTexCoord(l, r, t, b)

	if (pconf.classIcon) then
		self.classFrame:Show()
	else
		self.classFrame:Hide()
	end
end

-- XPerl_Player_UpdateRep
local function XPerl_Player_UpdateRep(self)
	if (pconf and pconf.repBar) then
		local rb = self.statsFrame.repBar
		if (rb) then
			local name, reaction, min, max, value = GetWatchedFactionInfo()
			local color

			if (name) then
				color = FACTION_BAR_COLORS[reaction]
			else
				name = XPERL_LOC_NONEWATCHED
				max = 1
				min = 0
				value = 0
				color = FACTION_BAR_COLORS[4]
			end

			value = value - min
			max = max - min
			min = 0

			rb:SetMinMaxValues(min, max)
			rb:SetValue(value)

			rb:SetStatusBarColor(color.r, color.g, color.b, 1)
			rb.bg:SetVertexColor(color.r, color.g, color.b, 0.25)

			local perc = (value * 100) / max
			rb.percent:SetFormattedText(perc1F, perc)

			if (max == 1) then
				rb.text:SetText(name)
			else
				rb.text:SetFormattedText("%d/%d", value, max)
			end
		end
	end
end

-- XPerl_Player_UpdateXP
local function XPerl_Player_UpdateXP(self)
	if (pconf.xpBar) then
		local xpBar = self.statsFrame.xpBar
		if (xpBar) then
			local restBar = self.statsFrame.xpRestBar
			local playerxp = UnitXP("player")
			local playerxpmax = UnitXPMax("player")
			local playerxprest = GetXPExhaustion() or 0
			xpBar:SetMinMaxValues(0, playerxpmax)
			restBar:SetMinMaxValues(0, playerxpmax)
			xpBar:SetValue(playerxp)

			local w = xpBar:GetRight() - xpBar:GetLeft()
			for mode = 1,3 do
				local suffix
				if (playerxprest > 0) then
					if (mode == 1) then
						suffix = format(" +%d", playerxprest)
					elseif (mode == 2) then
						if (playerxprest >= 1000000) then
							suffix = format(" +%.1fM", playerxprest / 1000000)
						else
							suffix = format(" +%.1fK", playerxprest / 1000)
						end
					else
						if (playerxprest >= 1000000) then
							suffix = format(" +%dM", playerxprest / 1000000)
						else
							suffix = format(" +%dK", playerxprest / 1000)
						end
					end

					color = {r = 0.3, g = 0.3, b = 1}
				else
					color = {r = 0.6, g = 0, b = 0.6}
				end

				if (pconf.xpDeficit) then
					XPerl_SetValuedText(xpBar.text, playerxp - playerxpmax, playerxpmax, suffix)
				else
					XPerl_SetValuedText(xpBar.text, playerxp, playerxpmax, suffix)
				end
				if (xpBar.text:GetStringWidth() <= w) then
					break
				end
			end

			xpBar:SetStatusBarColor(color.r, color.g, color.b, 1)
			xpBar.bg:SetVertexColor(color.r, color.g, color.b, 0.25)

			restBar:SetValue(playerxp + playerxprest)
			restBar:SetStatusBarColor(color.r, color.g, color.b, 0.5)
			restBar.bg:SetVertexColor(color.r, color.g, color.b, 0.5)

			xpBar.percent:SetFormattedText(percD, (playerxp * 100) / playerxpmax)
		end
	end
end

-- XPerl_Player_UpdatePVP
local function XPerl_Player_UpdatePVP(self)
	-- PVP Status settings
	local nf = self.nameFrame
	if (UnitAffectingCombat(self.partyid)) then
		nf.text:SetTextColor(1,0,0)
	else
		XPerl_ColourFriendlyUnit(nf.text, "player")
	end

	local pvp = pconf.pvpIcon and (UnitIsPVP("player") and UnitFactionGroup("player")) or (UnitIsPVPFreeForAll("player") and "FFA")
	if (pvp) then
		nf.pvp.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-"..pvp)
		nf.pvp:Show()
	else
		nf.pvp:Hide()
	end
end

-- XPerl_Player_DruidBarUpdate
local function XPerl_Player_DruidBarUpdate(self)
	local druidBar = self.statsFrame.druidBar
	local alternateKind, alternateValue, alternateMax, _, alternateColour = XPerl_Player_GetAlternateResource(self)
	local displayedPower = UnitPowerType(self.partyid) or 0
	local colourKey = alternateKind == "power" and secondaryPowerColours[alternateValue or 0] or alternateColour
	local colour = type(colourKey) == "table" and colourKey or (colourKey and conf.colour.bar[colourKey])
	local showAlternateBar = false

	if (alternateKind == "power") then
		showAlternateBar = alternateValue and (alternateValue ~= 0 and (UnitPowerMax(self.partyid, alternateValue) or 0) > 0 or ((self.cachedManaMax or 0) > 0))
	elseif (alternateKind == "aura") then
		showAlternateBar = (alternateMax or 0) > 0
	end

	if (showAlternateBar and not druidBar and MakeDruidBar) then
		MakeDruidBar(self)
		druidBar = self.statsFrame.druidBar
	end

	if (not druidBar) then
		return
	end

	local currMana, maxMana = 0, 0
	if (alternateKind == "power" and alternateValue == 0 and displayedPower ~= 0) then
		currMana = self.cachedMana or 0
		maxMana = self.cachedManaMax or 0
	elseif (alternateKind == "power" and alternateValue ~= nil) then
		currMana, maxMana = XPerl_Player_ReadPower(self.partyid, alternateValue)
	elseif (alternateKind == "aura") then
		currMana = alternateValue or 0
		maxMana = alternateMax or 0
	end

	druidBar:SetMinMaxValues(0, maxMana or 1)
	druidBar:SetValue(currMana or 0)
	if (alternateKind == "aura" and currMana and maxMana and currMana ~= floor(currMana)) then
		druidBar.text:SetFormattedText("%.1f/%d", currMana, maxMana or 1)
	else
		druidBar.text:SetFormattedText("%d/%d", ceil(currMana or 0), maxMana or 1)
	end
	if (colour) then
		druidBar:SetStatusBarColor(colour.r, colour.g, colour.b, 1)
		druidBar.bg:SetVertexColor(colour.r, colour.g, colour.b, 0.25)
	end

	if ((maxMana or 0) > 0) then
		druidBar.percent:SetFormattedText(percD, currMana * 100 / maxMana)
	else
		druidBar.percent:SetText("0%")
	end

	if (showAlternateBar) then
		druidBar.text:Show()
		if (pconf.percent) then
			druidBar.percent:Show()
		end
		druidBar:Show()
		druidBar:SetHeight(10)
	else
		druidBar.percent:Hide()
		druidBar.text:Hide()
		druidBar:Hide()
		druidBar:SetHeight(1)
	end

	if (self.statsFrame.alternateBarShown ~= showAlternateBar) then
		self.statsFrame.alternateBarShown = showAlternateBar
		local druidBarExtra = showAlternateBar and 1 or 0
		local h = 40 + ((druidBarExtra + (pconf.repBar or 0) + (pconf.xpBar or 0)) * 10)
		if (pconf.extendPortrait and not InCombatLockdown()) then
			self.portraitFrame:SetHeight(62 + druidBarExtra * 10 + (((pconf.xpBar or 0) + (pconf.repBar or 0)) * 10))
		end
		self.statsFrame:SetHeight(h)
		XPerl_StatsFrameSetup(self, {druidBar, self.statsFrame.xpBar, self.statsFrame.repBar})
		if (XPerl_Player_Buffs_Position) then
			XPerl_Player_Buffs_Position(self)
		end
	end
end

-- XPerl_Player_UpdateMana
local function XPerl_Player_UpdateMana(self)
	local mb = self.statsFrame.manaBar
	local displayedPower = UnitPowerType(self.partyid) or 0
	local playermana, playermanamax = XPerl_Player_ReadPower(self.partyid, displayedPower)
	if (displayedPower == 0) then
		self.cachedMana = playermana
		self.cachedManaMax = playermanamax
	end
	XPerl_Player_UpdateManaType(self)
	mb:SetMinMaxValues(0, playermanamax)
	mb:SetValue(playermana)

	mb.text:SetFormattedText("%d/%d", playermana, playermanamax)
	if (displayedPower >= 1 or playermanamax == 0) then
		mb.percent:SetText(playermana)
	else
		mb.percent:SetFormattedText(percD, (playermana * 100.0) / playermanamax)
	end
	if (not self.statsFrame.greyMana) then
		if (pconf.values) then
			mb.text:Show()
		end
		if (pconf.percent) then
			mb.percent:Show()
		end
	end

	if (XPerl_Player_ShouldShowAlternateMana(self) or (self.statsFrame.druidBar and self.statsFrame.druidBar:IsShown())) then
		XPerl_Player_DruidBarUpdate(self)
	end

	if (XPerl_Player_UsesAuraWidget(self) or (self.runes and self.runes.resourceType == "auraPips" and self.runes:IsShown())) then
		XPerl_Player_UpdateAuraPips(self)
	end
	XPerl_Player_UpdateCoAResourceBar(self)
end

local spiritOfRedemption = GetSpellInfo(27827)

-- XPerl_Player_UpdateHealth
function XPerl_Player_UpdateHealth(self)
	local partyid = self.partyid
	local sf = self.statsFrame
	local hb = sf.healthBar
	local playerhealth, playerhealthmax = XPerl_UnitHealth(partyid), UnitHealthMax(partyid)

	XPerl_SetHealthBar(self, playerhealth, playerhealthmax)

	local greyMsg
	if (UnitIsDead(partyid)) then
		--if (UnitIsFeignDeath("player")) then
		--	greyMsg = XPERL_LOC_FEIGNDEATH
		--else
			greyMsg = XPERL_LOC_DEAD
		--end

	elseif (UnitIsGhost(partyid)) then
		greyMsg = XPERL_LOC_GHOST

	elseif (UnitIsAFK("player") and conf.showAFK) then
		greyMsg = CHAT_MSG_AFK

	elseif (UnitBuff(partyid, spiritOfRedemption)) then
		greyMsg = XPERL_LOC_DEAD

	end

	if (greyMsg) then
		if (pconf.percent) then
			hb.percent:SetText(greyMsg)
			hb.percent:Show()
		else
			hb.text:SetText(greyMsg)
			hb.text:Show()
		end

		sf:SetGrey()
	else
		if (sf.greyMana) then
			if (not pconf.values) then
				hb.text:Hide()
			end

			sf.greyMana = nil
			XPerl_Player_UpdateManaType(self)
		end
	end

	XPerl_PlayerStatus_OnUpdate(self, playerhealth, playerhealthmax)
end

-- XPerl_Player_UpdateLevel
local function XPerl_Player_UpdateLevel(self)
	self.levelFrame.text:SetText(UnitLevel(self.partyid))
end

-- XPerl_PlayerStatus_OnUpdate
function XPerl_PlayerStatus_OnUpdate(self, val, max)
	if (pconf.fullScreen.enable) then
		local testLow = pconf.fullScreen.lowHP / 100
		local testHigh = pconf.fullScreen.highHP / 100

		if (val and max) then
			local test = val / max

			if ( test <= testLow and not XPerl_LowHealthFrame.frameFlash and not UnitIsDeadOrGhost("player")) then
				XPerl_FrameFlash(XPerl_LowHealthFrame)
			elseif ( (test >= testHigh and XPerl_LowHealthFrame.frameFlash) or UnitIsDeadOrGhost("player") ) then
				XPerl_FrameFlashStop(XPerl_LowHealthFrame, "out")
			end
			return
		else
			if (not UnitOnTaxi("player")) then
				if (isOutOfControl and not XPerl_OutOfControlFrame.frameFlash and not UnitOnTaxi("player")) then
					XPerl_FrameFlash(XPerl_OutOfControlFrame)
				elseif (not isOutOfControl and XPerl_OutOfControlFrame.frameFlash) then
					XPerl_FrameFlashStop(XPerl_OutOfControlFrame, "out")
				end
				return
			end
		end
	end

	if (XPerl_LowHealthFrame.frameFlash) then
		XPerl_FrameFlashStop(XPerl_LowHealthFrame)
	end
	if (XPerl_OutOfControlFrame.frameFlash) then
		XPerl_FrameFlashStop(XPerl_OutOfControlFrame)
	end
end

-- XPerl_Player_OnUpdate
function XPerl_Player_OnUpdate(self, elapsed)
	CombatFeedback_OnUpdate(self, elapsed)
	if (self.PlayerFlash) then
		XPerl_Player_CombatFlash(self, elapsed, false)
	end

	XPerl_Player_UpdateMana(self)
	
	-- Attempt to fix "not-updating bug", suggested by Taylla @ Curse
	-- comment 1st, 2nd and 4th line.
	-- if (self.updateAFK) then
	-- 	self.updateAFK = nil
	        XPerl_Player_UpdateHealth(self)
	-- end	

	if (IsResting() and UnitLevel("player") < MAX_PLAYER_LEVEL) then
		self.restingDelay = (self.restingDelay or 2) - elapsed
		if (self.restingDelay <= 0) then
			self.restingDelay = 2
			XPerl_Player_UpdateXP(self)
		end
	end

	if (self.updateAFK) then
		self.updateAFK = nil
		XPerl_Player_UpdateHealth(self)
	end
end

-- XPerl_Player_UpdateBuffs
local function XPerl_Player_UpdateBuffs(self)
	XPerl_CheckDebuffs(self, self.partyid)

	if (XPerl_Player_ShouldShowAlternateMana(self) or (self.statsFrame.druidBar and self.statsFrame.druidBar:IsShown())) then
		XPerl_Player_UpdateMana(self)
	end

	if (XPerl_Player_UsesAuraWidget(self) or (self.runes and self.runes.resourceType == "auraPips" and self.runes:IsShown())) then
		XPerl_Player_UpdateAuraPips(self)
	end

	if (pconf.fullScreen.enable) then
		if (isOutOfControl and not UnitOnTaxi("player")) then
			XPerl_PlayerStatus_OnUpdate(self)
		end
	end
end

-- XPerl_Player_UpdateDisplay
function XPerl_Player_UpdateDisplay (self)
	XPerl_Player_UpdateXP(self)
	XPerl_Player_UpdateRep(self)
	XPerl_Player_UpdateManaType(self)
	XPerl_Player_UpdateLevel(self)
	XPerl_Player_UpdateName(self)
	XPerl_Player_UpdateClass(self)
	XPerl_Player_UpdatePVP(self)
	XPerl_Player_UpdateCombat(self)
	XPerl_Player_UpdateLeader(self)
	XPerl_Player_UpdateMana(self)
	XPerl_Player_UpdateHealth(self)
	XPerl_Player_UpdateBuffs(self)
	XPerl_Player_UpdateAuraPips(self)
	XPerl_Player_UpdateCoAResourceBar(self)
	XPerl_Unit_UpdatePortrait(self)
end

-- EVENTS AND STUFF

-------------------
-- Event Handler --
-------------------
function XPerl_Player_OnEvent(self, event, arg1, ...)
	if (strsub(event, 1, 5) == "UNIT_") then
	 	if (arg1 == "player" or arg1 == "vehicle") then
			XPerl_Player_Events[event](self, ...)
		end
	else
		XPerl_Player_Events[event](self, arg1, ...)
	end
end

-- PLAYER_ENTERING_WORLD
function XPerl_Player_Events:PLAYER_ENTERING_WORLD()
	self.updateAFK = true
	if (UnitHasVehicleUI("player")) then
		self.partyid = "vehicle"
		self:SetAttribute("unit", "vehicle")
		if (XPerl_ArcaneBar_SetUnit) then
			XPerl_ArcaneBar_SetUnit(self.nameFrame, "vehicle")
		end
	else
		self.partyid = "player"
		self:SetAttribute("unit", "player")
		if (XPerl_ArcaneBar_SetUnit) then
			XPerl_ArcaneBar_SetUnit(self.nameFrame, "player")
		end
	end

	local events = {"UNIT_RAGE", "UNIT_MAXRAGE", "UNIT_MAXENERGY", "UNIT_MAXMANA", "UNIT_MAXRUNIC_POWER",
			"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_LEVEL", "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE",
			"UNIT_SPELLMISS", "UNIT_FACTION", "UNIT_PORTRAIT_UPDATE", "UNIT_FLAGS", "PLAYER_FLAGS_CHANGED",
			"UNIT_SPELLCAST_SUCCEEDED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
			"UNIT_SPELLCAST_SENT", "PLAYER_TALENT_UPDATE"}

	--XPerl_UnitEvents(self, XPerl_Player_Events, {"UNIT_SPELLMISS", "UNIT_FACTION", "UNIT_PORTRAIT_UPDATE",
	--						"UNIT_FLAGS", "PLAYER_FLAGS_CHANGED", "UNIT_SPELLCAST_SUCCEEDED"})
	--XPerl_RegisterBasics(self, XPerl_Player_Events)

	for i,e in pairs(events) do
		self:RegisterEvent(e)
	end

	XPerl_Player_UpdateDisplay(self)
end

-- UNIT_COMBAT
function XPerl_Player_Events:UNIT_COMBAT(...)
	if (arg1 == self.partyid) then
		if (pconf.hitIndicator and pconf.portrait) then
			if (arg2 ~= "HEAL" or UnitHealth(self.partyid) < UnitHealthMax(self.partyid)) then
				CombatFeedback_OnCombatEvent(self, ...)
			end
		end

		if (arg2 == "HEAL") then
			XPerl_Player_CombatFlash(self, elapsed, true, true)
		elseif (arg4 and arg4 > 0) then
			XPerl_Player_CombatFlash(self, elapsed, true)
		end
	end
end

-- UNIT_SPELLMISS
function XPerl_Player_Events:UNIT_SPELLMISS(...)
	if (pconf.hitIndicator and pconf.portrait) then
		if (arg1 == self.partyid) then
			CombatFeedback_OnSpellMissEvent(self, ...)
		end
	end
end

-- UNIT_PORTRAIT_UPDATE
function XPerl_Player_Events:UNIT_PORTRAIT_UPDATE()
	XPerl_Unit_UpdatePortrait(self)
end

-- VARIABLES_LOADED
function XPerl_Player_Events:VARIABLES_LOADED()
	self.doubleCheckAFK = 2		-- Check during 2nd UPDATE_FACTION, which are the last guarenteed events to come after logging in
	self:UnregisterEvent(event)

	local events = {"PLAYER_ENTERING_WORLD", "PARTY_MEMBERS_CHANGED", "PARTY_LEADER_CHANGED",
			"PARTY_LOOT_METHOD_CHANGED", "RAID_ROSTER_UPDATE", "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_ENABLED",
			"PLAYER_REGEN_DISABLED", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "PLAYER_DEAD",
			"UPDATE_FACTION", "UNIT_AURA", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
			"UNIT_COMBAT"}

	for i,event in pairs(events) do
		self:RegisterEvent(event)
	end

	XPerl_Player_Events.VARIABLES_LOADED = nil
end

-- PARTY_LOOT_METHOD_CHANGED
function XPerl_Player_Events:PARTY_LOOT_METHOD_CHANGED()
	XPerl_Player_UpdateLeader(self)
end
XPerl_Player_Events.PARTY_MEMBERS_CHANGED	= XPerl_Player_Events.PARTY_LOOT_METHOD_CHANGED
XPerl_Player_Events.PARTY_LEADER_CHANGED	= XPerl_Player_Events.PARTY_LOOT_METHOD_CHANGED
XPerl_Player_Events.RAID_ROSTER_UPDATE		= XPerl_Player_Events.PARTY_LOOT_METHOD_CHANGED

-- UNIT_HEALTH, UNIT_MAXHEALTH
function XPerl_Player_Events:UNIT_HEALTH()
	XPerl_Player_UpdateHealth(self)
end
XPerl_Player_Events.UNIT_MAXHEALTH = XPerl_Player_Events.UNIT_HEALTH
XPerl_Player_Events.PLAYER_DEAD    = XPerl_Player_Events.UNIT_HEALTH

function XPerl_Player_Events:UNIT_SPELLCAST_SENT(spell, rank, targetName, castID)
	if (pconf.energyTicker and spell and UnitPowerMax(self.partyid, 0) > 0) then
		self.tickerPrevMana = UnitPower(self.partyid, 0)
		self:UnregisterEvent("UNIT_MANA")
	end
end

-- checkUsedMana
local function checkUsedMana(self)
	if (self.tickerPrevMana and UnitPower(self.partyid, 0) < self.tickerPrevMana) then
		local diffTime = GetTime() - self.tickerCastTime
		self.statsFrame.energyTicker:SetValue(diffTime)
		self.statsFrame.energyTicker:Show()
		return true
	end
end

-- UNIT_SPELLCAST_SUCCEEDED
function XPerl_Player_Events:UNIT_SPELLCAST_SUCCEEDED(spell, rank, castID)
	if (pconf.energyTicker and spell and UnitPowerMax(self.partyid, 0) > 0) then
		self.tickerCastTime = GetTime()
		if (not checkUsedMana(self)) then
			self.waitForManaReduction = true
			self:RegisterEvent("UNIT_MANA")
		end
	end
end

-- UNIT_MANA
function XPerl_Player_Events:UNIT_MANA()
	XPerl_Player_UpdateMana(self)

	if (self.waitForManaReduction) then
		checkUsedMana(self)

		self.waitForManaReduction = nil
		self.tickerPrevMana = nil
		self.tickerCastTime = nil
		self:UnregisterEvent("UNIT_MANA")
	end
end

-- UNIT_MAXMANA
function XPerl_Player_Events:UNIT_MAXMANA()
	XPerl_Player_UpdateMana(self)
end

XPerl_Player_Events.UNIT_RAGE			= XPerl_Player_Events.UNIT_MAXMANA
XPerl_Player_Events.UNIT_MAXRAGE		= XPerl_Player_Events.UNIT_RAGE
XPerl_Player_Events.UNIT_RUNIC_POWER	= XPerl_Player_Events.UNIT_MAXMANA
XPerl_Player_Events.UNIT_MAXRUNIC_POWER	= XPerl_Player_Events.UNIT_RUNIC_POWER
XPerl_Player_Events.UNIT_ENERGY			= XPerl_Player_Events.UNIT_MAXMANA
XPerl_Player_Events.UNIT_MAXENERGY		= XPerl_Player_Events.UNIT_ENERGY

-- UNIT_DISPLAYPOWER
function XPerl_Player_Events:UNIT_DISPLAYPOWER()
	XPerl_Player_UpdateManaType(self)
	XPerl_Player_UpdateMana(self)
end

-- UNIT_NAME_UPDATE
function XPerl_Player_Events:UNIT_NAME_UPDATE()
	XPerl_Player_UpdateName(self)
end

-- UNIT_LEVEL
function XPerl_Player_Events:UNIT_LEVEL()
	XPerl_Player_UpdateLevel(self)
	XPerl_Player_UpdateXP(self)
end
XPerl_Player_Events.PLAYER_LEVEL_UP = XPerl_Player_Events.UNIT_LEVEL

-- PLAYER_XP_UPDATE
function XPerl_Player_Events:PLAYER_XP_UPDATE()
	XPerl_Player_UpdateXP(self)
end

-- UPDATE_FACTION
function XPerl_Player_Events:UPDATE_FACTION()
	XPerl_Player_UpdateRep(self)

	if (self.doubleCheckAFK) then
		if (conf and pconf) then
			self.doubleCheckAFK = self.doubleCheckAFK - 1
			if (self.doubleCheckAFK <= 0) then
				XPerl_Player_UpdateHealth(self)
				self.doubleCheckAFK = nil
			end
		end
	end
end

-- UNIT_FACTION
function XPerl_Player_Events:UNIT_FACTION()
	XPerl_Player_UpdateHealth(self)
	XPerl_Player_UpdatePVP(self)
	XPerl_Player_UpdateCombat(self)
end
XPerl_Player_Events.UNIT_FLAGS = XPerl_Player_Events.UNIT_FACTION

function XPerl_Player_Events:PLAYER_FLAGS_CHANGED(unit)
	XPerl_Player_UpdateHealth(self)
end

-- PLAYER_TALENT_UPDATE
function XPerl_Player_Events:PLAYER_TALENT_UPDATE()
	XPerl_Player_UpdateMana(self)
	if (XPerl_Player_ShouldShowAlternateMana(self) or (self.statsFrame.druidBar and self.statsFrame.druidBar:IsShown())) then
		XPerl_Player_DruidBarUpdate(self)
	end
end

-- PLAYER_ENTER_COMBAT, PLAYER_LEAVE_COMBAT
function XPerl_Player_Events:PLAYER_ENTER_COMBAT()
	XPerl_Player_UpdateCombat(self)
end
XPerl_Player_Events.PLAYER_LEAVE_COMBAT = XPerl_Player_Events.PLAYER_ENTER_COMBAT

-- PLAYER_REGEN_ENABLED
function XPerl_Player_Events:PLAYER_REGEN_ENABLED()
	XPerl_Player_UpdateCombat(self)

	if (self:GetAttribute("unit") ~= self.partyid) then
		self:SetAttribute("unit", self.partyid)
		XPerl_Player_UpdateDisplay(self)
	end
end

-- PLAYER_REGEN_DISABLED
function XPerl_Player_Events:PLAYER_REGEN_DISABLED()
	XPerl_Player_UpdateCombat(self)
end

function XPerl_Player_Events:PLAYER_UPDATE_RESTING()
	XPerl_Player_UpdateCombat(self)
	XPerl_Player_UpdateXP(self)
end

function XPerl_Player_Events:UNIT_AURA()
	XPerl_Player_UpdateBuffs(self)
end

-- PLAYER_CONTROL_LOST
function XPerl_Player_Events:PLAYER_CONTROL_LOST()
	if (pconf.fullScreen.enable and not UnitOnTaxi("player")) then
		isOutOfControl = 1
	end
end

-- PLAYER_CONTROL_GAINED
function XPerl_Player_Events:PLAYER_CONTROL_GAINED()
	isOutOfControl = nil
	if (pconf.fullScreen.enable) then
		XPerl_PlayerStatus_OnUpdate(self)
	end
end

-- UNIT_ENTERED_VEHICLE
function XPerl_Player_Events:UNIT_ENTERED_VEHICLE(showVehicle)
	if (showVehicle) then
		self.partyid = "vehicle"
		if (XPerl_ArcaneBar_SetUnit) then
			XPerl_ArcaneBar_SetUnit(self.nameFrame, "vehicle")
		end
		if (not InCombatLockdown()) then
			self:SetAttribute("unit", "vehicle")
		end
		XPerl_Player_UpdateDisplay(self)
	end
end

-- UNIT_EXITED_VEHICLE
function XPerl_Player_Events:UNIT_EXITED_VEHICLE()
	if (self.partyid ~= "player") then
		self.partyid = "player"
		if (XPerl_ArcaneBar_SetUnit) then
			XPerl_ArcaneBar_SetUnit(self.nameFrame, "player")
		end
		if (not InCombatLockdown()) then
			self:SetAttribute("unit", "player")
		end
		XPerl_Player_UpdateDisplay(self)
	end
end

-- XPerl_Player_Energy_TickWatch
function XPerl_Player_Energy_OnUpdate(self, elapsed)
	local sparkPosition

	local val = self:GetValue() + elapsed
	if (val > 5) then
		self:Hide()
	else
		self:SetValue(val)
		sparkPosition = self:GetWidth() * (val / 5)
	end

	self.spark:SetPoint("CENTER", self, "LEFT", sparkPosition, 0)
end

-- XPerl_Player_SetWidth
function XPerl_Player_SetWidth(self)

	pconf.size.width = max(0, pconf.size.width or 0)
	if (pconf.percent) then
		self.nameFrame:SetWidth(160 + pconf.size.width)
		self.statsFrame:SetWidth(160 + pconf.size.width)
		self.statsFrame.healthBar.percent:Show()
		self.statsFrame.manaBar.percent:Show()

		if (self.statsFrame.xpBar) then
			self.statsFrame.xpBar.percent:Show()
		end
		if (self.statsFrame.repBar) then
			self.statsFrame.repBar.percent:Show()
		end
	else
		self.nameFrame:SetWidth(128 + pconf.size.width)
		self.statsFrame:SetWidth(128 + pconf.size.width)
		self.statsFrame.healthBar.percent:Hide()
		self.statsFrame.manaBar.percent:Hide()
		if (self.statsFrame.xpBar) then
			self.statsFrame.xpBar.percent:Hide()
		end
		if (self.statsFrame.repBar) then
			self.statsFrame.repBar.percent:Hide()
		end
	end

	local h = 40 + ((((self.statsFrame.druidBar and self.statsFrame.druidBar:IsShown()) or 0) + (pconf.repBar or 0) + (pconf.xpBar or 0)) * 10)
	self.statsFrame:SetHeight(h)

	self:SetWidth((pconf.portrait or 0) * 62 + (pconf.percent or 0) * 32 + 124 + pconf.size.width)
	self:SetScale(pconf.scale)

	XPerl_StatsFrameSetup(self, {self.statsFrame.druidBar, self.statsFrame.xpBar, self.statsFrame.repBar})
	if (XPerl_Player_Buffs_Position) then
		XPerl_Player_Buffs_Position(self)
	end

	XPerl_Player_UpdateHealth(self)
	XPerl_Player_UpdateMana(self)
	XPerl_Player_UpdateXP(self)

	XPerl_SavePosition(self, true)
	XPerl_RestorePosition(self)
end

-- CreateBar(self, name)
local function CreateBar(self, name)
	local f = CreateFrame("StatusBar", self.statsFrame:GetName()..name, self.statsFrame, "XPerlStatusBar")
	f:SetPoint("TOPLEFT", self.statsFrame.manaBar, "BOTTOMLEFT", 0, 0)
	f:SetHeight(10)
	self.statsFrame[name] = f
	f:SetWidth(112)
	return f
end

-- MakeEnergyTicker
local function MakeEnergyTicker(self)
	local f = CreateFrame("StatusBar", self.statsFrame:GetName().."energyTicker", self.statsFrame.manaBar)
	self.statsFrame.energyTicker = f
	f:SetPoint("TOPLEFT", self.statsFrame.manaBar, "BOTTOMLEFT", 0, 0)
	f:SetPoint("BOTTOMRIGHT", self.statsFrame.manaBar, "BOTTOMRIGHT", 0, -2)
	f:SetStatusBarTexture("Interface\\AddOns\\XPerl_CoA\\Images\\XPerl_FrameBack")
	f:SetHeight(2)
	--f:SetFrameLevel(self.statsFrame.manaBar:GetFrameLevel() + 1)
	f:Hide()

	f.spark = f:CreateTexture(nil, "OVERLAY")
	f.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	f.spark:SetBlendMode("ADD")
	f.spark:SetWidth(12)
	f.spark:SetHeight(12)
	f.spark:SetPoint("CENTER", 0, 0)

	f:SetStatusBarColor(0.4, 0.7, 1)
	f.spark:SetVertexColor(0.4, 0.7, 1)
	f:SetMinMaxValues(0, 5)

	f.EnergyTime = 0
	f:SetScript("OnUpdate", XPerl_Player_Energy_OnUpdate)

	MakeEnergyTicker = nil
end

-- MakeDruidBar()
local function MakeDruidBar(self)
	local f = CreateBar(self, "druidBar")
	local c = conf.colour.bar.mana
	f:SetStatusBarColor(c.r, c.g, c.b)
	f.bg:SetVertexColor(c.r, c.g, c.b, 0.25)
	MakeDruidBar = nil
end

-- MakeXPBars
local function MakeXPBars(self)
	local f = CreateBar(self, "xpBar")
	local f2 = CreateBar(self, "xpRestBar")

	f2:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f2:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

	MakeXPBars = nil
end

-- XPerl_Player_SetTotems
function XPerl_Player_SetTotems(self, ...)
	if (pconf.totems and pconf.totems.enable) then
		TotemFrame:SetParent(XPerl_Player)
		TotemFrame:ClearAllPoints()
		TotemFrame:SetPoint("TOP", XPerl_Player, "BOTTOM", pconf.totems.offsetX, pconf.totems.offsetY)
	else
		TotemFrame:SetParent(PlayerFrame)
		TotemFrame:ClearAllPoints()
		TotemFrame:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", 99, 38)
	end
end

-- XPerl_Player_Set_Bits()
function XPerl_Player_Set_Bits(self)
	if (XPerl_ArcaneBar_RegisterFrame and not self.nameFrame.castBar) then
		XPerl_ArcaneBar_RegisterFrame(self.nameFrame, UnitHasVehicleUI("player") and "vehicle" or "player")
	end

	if (pconf.portrait) then
		self.portraitFrame:Show()
		self.portraitFrame:SetWidth(60)
	else
		self.portraitFrame:Hide()
		self.portraitFrame:SetWidth(3)
	end

	if (pconf.level) then
		self.levelFrame:Show()
		self:RegisterEvent("PLAYER_LEVEL_UP")
	else
		self.levelFrame:Hide()
	end

	XPerl_Player_UpdateClass(self)

	if (pconf.repBar) then
		if (not self.statsFrame.repBar) then
			CreateBar(self, "repBar")
		end

		self.statsFrame.repBar:Show()
	else
		if (self.statsFrame.repBar) then
			self.statsFrame.repBar:Hide()
		end
	end

	if (pconf.energyTicker) then
		if (not self.statsFrame.energyTicker) then
			MakeEnergyTicker(self)
		end
	end

	if (XPerl_Player_ShouldShowAlternateMana(self) and not self.statsFrame.druidBar) then
		MakeDruidBar(self)
	end

	if (pconf.xpBar) then
		if (not self.statsFrame.xpBar) then
			MakeXPBars(self)
		end

		self.statsFrame.xpBar:Show()
		self.statsFrame.xpRestBar:Show()

		self:RegisterEvent("PLAYER_XP_UPDATE")
	else
		if (self.statsFrame.xpBar) then
			self.statsFrame.xpBar:Hide()
			self.statsFrame.xpRestBar:Hide()
		end

		self:UnregisterEvent("PLAYER_XP_UPDATE")
	end

	if (pconf.values) then
		self.statsFrame.healthBar.text:Show()
		self.statsFrame.manaBar.text:Show()
		if (self.statsFrame.xpBar) then
			self.statsFrame.xpBar.text:Show()
		end
		if (self.statsFrame.repBar) then
			self.statsFrame.repBar.text:Show()
		end
	else
		self.statsFrame.healthBar.text:Hide()
		self.statsFrame.manaBar.text:Hide()
		if (self.statsFrame.xpBar) then
			self.statsFrame.xpBar.text:Hide()
		end
		if (self.statsFrame.repBar) then
			self.statsFrame.repBar.text:Hide()
		end
	end

	XPerl_Player_SetWidth(self)

	local h1 = self.nameFrame:GetHeight() + self.statsFrame:GetHeight() - 2
	local h2 = self.portraitFrame:GetHeight()
	XPerl_SwitchAnchor(self, "TOPLEFT")
	self:SetHeight(max(h1, h2))

	self.highlight:ClearAllPoints()
	if (pconf.extendPortrait or (self.runes and pconf.showRunes and pconf.dockRunes)) then
		self.portraitFrame:SetHeight(62 + (((pconf.xpBar or 0) + (pconf.repBar or 0)) * 10))
		--self.highlight:SetPoint("TOPLEFT", self.levelFrame, "TOPLEFT", 0, 0)
		--self.highlight:SetPoint("BOTTOMRIGHT", self.statsFrame, "BOTTOMRIGHT", 0, 0)
	else
		self.portraitFrame:SetHeight(62)
		--self.highlight:SetPoint("BOTTOMLEFT", self.classFrame, "BOTTOMLEFT", -2, -2)
		--self.highlight:SetPoint("TOPRIGHT", self.nameFrame, "TOPRIGHT", 0, 0)
	end

	if (self.runes and self.runes.resourceType == "auraPips") then
		XPerl_Player_SetupAuraPips(self)
	else
		XPerl_Player_SetupDK(self)
	end

	self.highlight:ClearAllPoints()
	if (not pconf.level and not pconf.classIcon and (not XPerlConfigHelper or XPerlConfigHelper.ShowTargetCounters == 0)) then
		self.highlight:SetPoint("TOPLEFT", self.portraitFrame, "TOPLEFT", 0, 0)
	else
		self.highlight:SetPoint("TOPLEFT", self.levelFrame, "TOPLEFT", 0, 0)
	end
	self.highlight:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)

	if (playerClass == "SHAMAN") then
		if (not pconf.totems) then
			pconf.totems = {
				enable = true,
				offsetX = 0,
				offsetY = 0
			}
		end

		if (not self.totemHooked) then
			self.totemHooked = true
			hooksecurefunc("TotemFrame_Update", XPerl_Player_SetTotems)
		end
	end
	
	self:SetAlpha(conf.transparency.frame)

	self.buffOptMix = nil
	XPerl_Player_UpdateDisplay(self)

	if (XPerl_Player_BuffSetup) then
		if (self.buffFrame) then
			self.buffOptMix = nil
			XPerl_Player_BuffSetup(XPerl_Player)
		end
	end

	if (XPerl_Voice) then
		XPerl_Voice:Register(self)
	end

	UpdateAssignedRoles(self)
end

-- XPerl_Player_InitDK
function XPerl_Player_InitDK(self)
	if (select(2, UnitClass("player")) == "DEATHKNIGHT") then
		if (not RuneFrame or RuneFrame:GetParent() ~= UIParent or not RuneFrame:IsShown()) then
			-- Only hijack runes if not already done so by another mod
			return
		end

		local p, f, r, x, y = RuneFrame:GetPoint(1)
		if (f ~= PlayerFrame or p ~= "TOP" or r ~= "BOTTOM") then
			-- More safety checking before we fudge it
			return
		end

		self.runes = CreateFrame("Frame", "XPerl_Runes", self)
		self.runes:SetPoint("TOPLEFT", self.portraitFrame, "BOTTOMLEFT", 0, 2)
		self.runes:SetPoint("BOTTOMRIGHT", self.statsFrame, "BOTTOMRIGHT", 0, -30)

		self.runes:SetMovable(true)
		self.runes:RegisterForDrag("LeftButton")
		self.runes:SetScript("OnDragStart",
			function(self)
				if (not pconf.dockRunes) then
					self:StartMoving()
				end
			end)
		self.runes:SetScript("OnDragStop",
			function(self)
				if (not pconf.dockRunes) then
					self:StopMovingOrSizing()
					XPerl_SavePosition(self)
				end
			end)

		local bgDef = {bgFile = "Interface\\AddOns\\XPerl_CoA\\Images\\XPerl_FrameBack",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 32, edgeSize = 12,
				insets = { left = 3, right = 3, top = 3, bottom = 3 }
			}
		self.runes:SetBackdrop(bgDef)
		self.runes:SetBackdropColor(0, 0, 0, 0.8)
		self.runes:SetBackdropBorderColor(1, 1, 1, 1)
		self.runes.list = {}

		RuneFrame:SetParent(self.runes)
		RuneFrame:ClearAllPoints()
		RuneFrame:SetPoint("TOPLEFT", 5, -5)
		RuneFrame:SetPoint("BOTTOMRIGHT", -5, 5)

		for i = 1,6 do
			local rune = RuneFrame.runes[i]
			if (rune) then
				rune:Hide()
			end
		end

		RuneFrame.runes = {}

		local prev
		local idSwitch = {1, 2, 5, 6, 3, 4}		-- Non sequential rune IDs.. gg
		for i = 1,6 do
			local rune = CreateFrame("Button", "XPerl_RuneButtonIndividual"..i, RuneFrame, "XPerl_RuneButtonIndividualTemplate")
			self.runes.list[i] = rune
			rune:EnableMouse(false)

			-- god only knows why blizzard did this...
			rune:SetID(idSwitch[i])

			if (i > 1) then
				rune:SetPoint("LEFT", prev, "RIGHT", 4 + ((i % 2) * 16), 0)
			else
				rune:SetPoint("LEFT", 10, 0)
			end
			prev = rune
		end
	end
	
	XPerl_Player_InitDK = nil
end

function XPerl_Player_InitAuraPips(self)
	if (self.runes or not XPerl_Player_UsesAuraWidget(self)) then
		return
	end

	local definition = XPerl_Player_GetAuraResourceDefinition(self)
	if (definition.display == "badge") then
		local fillColour = definition.fillColour or {r = 0.95, g = 0.76, b = 0.24}
		local runesTopOffset = (definition and definition.barAuras) and -2 or 2
		local runesBottomOffset = (definition and definition.barAuras) and -34 or -30
		self.runes = CreateFrame("Frame", "XPerl_AuraPips", self)
		self.runes.resourceType = "auraPips"
		self.runes:SetPoint("TOPLEFT", self.portraitFrame, "BOTTOMLEFT", 0, runesTopOffset)
		self.runes:SetPoint("BOTTOMRIGHT", self.statsFrame, "BOTTOMRIGHT", 0, runesBottomOffset)
		self.runes:SetMovable(true)
		self.runes:RegisterForDrag("LeftButton")
		self.runes:SetScript("OnDragStart",
			function(this)
				if (not pconf.dockRunes) then
					this:StartMoving()
				end
			end)
		self.runes:SetScript("OnDragStop",
			function(this)
				if (not pconf.dockRunes) then
					this:StopMovingOrSizing()
					XPerl_SavePosition(this)
				end
			end)

		local bgDef = {bgFile = "Interface\\AddOns\\XPerl_CoA\\Images\\XPerl_FrameBack",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 32, edgeSize = 12,
				insets = { left = 3, right = 3, top = 3, bottom = 3 }
			}
		self.runes:SetBackdrop(bgDef)
		self.runes:SetBackdropColor(0, 0, 0, 0.8)
		self.runes:SetBackdropBorderColor(1, 1, 1, 1)
		self.runes.list = {}

		local pip = CreateFrame("Frame", nil, self.runes)
		pip:SetWidth(40)
		pip:SetHeight(40)
		pip.base = pip:CreateTexture(nil, "ARTWORK")
		pip.base:SetTexture("Interface\\ComboFrame\\ComboPoint")
		pip.base:SetTexCoord(0.5625, 1, 0, 1)
		pip.base:SetAllPoints()
		pip.base:SetBlendMode("BLEND")

		pip.fill = pip:CreateTexture(nil, "OVERLAY")
		pip.fill:SetTexture("Interface\\ComboFrame\\ComboPoint")
		pip.fill:SetTexCoord(0.5625, 1, 0, 1)
		pip.fill:SetAllPoints()
		pip.fill:SetBlendMode("BLEND")

		pip.badgeGlow = pip:CreateTexture(nil, "OVERLAY")
		pip.badgeGlow:SetTexture("Interface\\ComboFrame\\ComboPoint")
		pip.badgeGlow:SetTexCoord(0.5625, 1, 0, 1)
		pip.badgeGlow:SetAllPoints()
		pip.badgeGlow:SetBlendMode("ADD")

		pip.crossH = pip:CreateTexture(nil, "BORDER")
		pip.crossH:SetTexture("Interface\\AddOns\\XPerl_CoA\\Images\\XPerl_FrameBack")
		pip.crossH:SetWidth(22)
		pip.crossH:SetHeight(4)
		pip.crossH:SetPoint("CENTER", pip, "CENTER", 0, -3)
		pip.crossH:SetVertexColor(fillColour.r, fillColour.g, fillColour.b)

		pip.crossV = pip:CreateTexture(nil, "BORDER")
		pip.crossV:SetTexture("Interface\\AddOns\\XPerl_CoA\\Images\\XPerl_FrameBack")
		pip.crossV:SetWidth(4)
		pip.crossV:SetHeight(22)
		pip.crossV:SetPoint("CENTER", pip, "CENTER", 0, -3)
		pip.crossV:SetVertexColor(fillColour.r, fillColour.g, fillColour.b)

		pip.badgeText = pip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		pip.badgeText:SetPoint("LEFT", pip, "RIGHT", 10, 0)
		pip.badgeText:SetJustifyH("LEFT")
		pip.badgeText:SetText("+0%")

		pip.badgeCount = pip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		pip.badgeCount:SetPoint("BOTTOM", pip, "BOTTOM", 0, 2)
		pip.badgeCount:SetText("0")

		pip.fragments = {}
		pip.fragmentBacks = {}
		self.runes.list[1] = pip
		return
	end

	local pipCount = (definition and definition.max) or 3
	local segmentCount = (definition and definition.segments) or 3
	if (segmentCount < 1) then
		segmentCount = 1
	end

	self.runes = CreateFrame("Frame", "XPerl_AuraPips", self)
	self.runes.resourceType = "auraPips"
	self.runes.pipCount = pipCount
	self.runes.segmentCount = segmentCount
	self.runes:SetPoint("TOPLEFT", self.portraitFrame, "BOTTOMLEFT", 0, 2)
	self.runes:SetPoint("BOTTOMRIGHT", self.statsFrame, "BOTTOMRIGHT", 0, -30)
	self.runes:SetMovable(true)
	self.runes:RegisterForDrag("LeftButton")
	self.runes:SetScript("OnDragStart",
		function(this)
			if (not pconf.dockRunes) then
				this:StartMoving()
			end
		end)
	self.runes:SetScript("OnDragStop",
		function(this)
			if (not pconf.dockRunes) then
				this:StopMovingOrSizing()
				XPerl_SavePosition(this)
			end
		end)

	local bgDef = {bgFile = "Interface\\AddOns\\XPerl_CoA\\Images\\XPerl_FrameBack",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 32, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 }
		}
	self.runes:SetBackdrop(bgDef)
	self.runes:SetBackdropColor(0, 0, 0, 0.8)
	self.runes:SetBackdropBorderColor(1, 1, 1, 1)
	self.runes.list = {}

	for i = 1,pipCount do
		local pip = CreateFrame("Frame", nil, self.runes)
		pip:SetWidth(28)
		pip:SetHeight(28)
		pip.base = pip:CreateTexture(nil, "ARTWORK")
		pip.base:SetTexture("Interface\\ComboFrame\\ComboPoint")
		pip.base:SetTexCoord(0.5625, 1, 0, 1)
		pip.base:SetAllPoints()
		pip.base:SetBlendMode("ADD")

		pip.fill = pip:CreateTexture(nil, "OVERLAY")
		pip.fill:SetTexture("Interface\\ComboFrame\\ComboPoint")
		pip.fill:SetTexCoord(0.5625, 1, 0, 1)
		pip.fill:SetAllPoints()
		pip.fill:SetBlendMode("ADD")

		pip.fragments = {}
		pip.fragmentBacks = {}
		if (segmentCount > 1) then
			for fragmentIndex = 1,segmentCount do
				local fragmentBack = pip:CreateTexture(nil, "BORDER")
				fragmentBack:SetTexture("Interface\\AddOns\\XPerl_CoA\\Images\\XPerl_FrameBack")
				fragmentBack:SetWidth(20)
				fragmentBack:SetHeight(5)
				fragmentBack:SetPoint("TOP", pip, "TOP", 0, -4 - ((fragmentIndex - 1) * 7))
				fragmentBack:Hide()
				pip.fragmentBacks[fragmentIndex] = fragmentBack

				local fragment = pip:CreateTexture(nil, "OVERLAY")
				fragment:SetTexture("Interface\\AddOns\\XPerl_CoA\\Images\\XPerl_FrameBack")
				fragment:SetWidth(20)
				fragment:SetHeight(5)
				fragment:SetPoint("TOP", pip, "TOP", 0, -4 - ((fragmentIndex - 1) * 7))
				fragment:SetBlendMode("BLEND")
				fragment:Hide()
				pip.fragments[fragmentIndex] = fragment
			end
		end

		self.runes.list[i] = pip
	end
end

function XPerl_Player_SetupAuraPips(self)
	if (not self.runes or self.runes.resourceType ~= "auraPips") then
		return
	end

	if (not pconf or pconf.showRunes) then
		self.runes:Show()
		self.runes:ClearAllPoints()
		local definition = XPerl_Player_GetAuraResourceDefinition(self)
		local runesTopOffset = (definition and definition.barAuras) and -2 or 2
		local runesBottomOffset = (definition and definition.barAuras) and -34 or -30
		if (not pconf or pconf.dockRunes) then
			self.runes:SetPoint("TOPLEFT", self.portraitFrame, "BOTTOMLEFT", 0, runesTopOffset)
			self.runes:SetPoint("BOTTOMRIGHT", self.statsFrame, "BOTTOMRIGHT", 0, runesBottomOffset)
		else
			self.runes:SetPoint("TOPLEFT", self.portraitFrame, "BOTTOMLEFT", 0, runesTopOffset)
			self.runes:SetWidth(214)
			self.runes:SetHeight(32)
			XPerl_RestorePosition(self.runes)
		end

		if (definition.display == "badge") then
			local pip = self.runes.list[1]
			if (pip) then
				pip:ClearAllPoints()
				pip:SetWidth(40)
				pip:SetHeight(40)
				pip:SetPoint("CENTER", self.runes, "CENTER", -18, 0)
			end
		else
			local prev
			local pipCount = #self.runes.list
			local pipSize = pipCount > 4 and 22 or 28
			local spacing = pipCount > 4 and 10 or (pipCount > 3 and 16 or 26)
			local pipOffsetY = (definition and definition.barAuras) and -3 or -4
			if (pipCount > 4) then
				pipOffsetY = pipOffsetY + 2
			end
			local totalWidth = (pipCount * pipSize) + ((pipCount - 1) * spacing)
			for index, pip in ipairs(self.runes.list) do
				pip:ClearAllPoints()
				pip:SetWidth(pipSize)
				pip:SetHeight(pipSize)
				if (index == 1) then
					pip:SetPoint("CENTER", self.runes, "CENTER", -floor(totalWidth / 2) + floor(pipSize / 2), pipOffsetY)
				else
					pip:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
				end
				prev = pip
			end
		end
	else
		self.runes:Hide()
		self.runes:SetScript("OnUpdate", nil)
	end

	XPerl_Player_UpdateAuraPips(self)
end

-- XPerl_Player_SetupDK
function XPerl_Player_SetupDK(self)
	if (self.runes) then
		if (not pconf or pconf.showRunes) then
			self.runes:Show()

			self.runes:ClearAllPoints()
			if (not pconf or pconf.dockRunes) then
				self.runes:SetPoint("TOPLEFT", self.portraitFrame, "BOTTOMLEFT", 0, 2)
				self.runes:SetPoint("BOTTOMRIGHT", self.statsFrame, "BOTTOMRIGHT", 0, -30)
			else
				self.runes:SetPoint("TOPLEFT", self.portraitFrame, "BOTTOMLEFT", 0, 2)
				self.runes:SetWidth(214)
				self.runes:SetHeight(32)
				XPerl_RestorePosition(self.runes)
			end

			for i = 1,6 do
				local rune = getglobal("XPerl_RuneButtonIndividual"..i)
				self.runes.list[i] = rune
				rune:ClearAllPoints()
				rune:SetWidth(22)
				rune:SetHeight(22)

				if (self.runes:GetWidth() >= 200) then	-- pconf.portrait) then
					if (i > 1) then
						rune:SetPoint("LEFT", prev, "RIGHT", 4 + ((i % 2) * 16), 0)
					else
						rune:SetPoint("LEFT", 10, 0)
					end
				else
					if (i > 1) then
						rune:SetPoint("LEFT", prev, "RIGHT", 1 + ((i % 2) * 5), 0)
					else
						rune:SetPoint("LEFT", 1, 0)
					end
				end
				prev = rune
			end
		else
			self.runes:Hide()
		end
	end
end
