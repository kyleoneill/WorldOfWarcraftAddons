-- Put everything in the addon inside a unique global table to avoid name collision
CustomDPS = {};

-- Queue
CustomDPS.Queue = {};
CustomDPS.windowLengthInSeconds = 60;

-- Global variables
CustomDPS.timeBuffer = 0;
CustomDPS.inCombat = false;
CustomDPS.updateInterval = 1;
CustomDPS.playerName = nil;
CustomDPS.dps = 0;
CustomDPS.party = {};

-- Frames to contain addon functions
CustomDPS.CustomDPSFrame = CreateFrame("Frame", "CustomDPSFrame");
CustomDPS.CustomDPSFrame.MsgFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate");

-- Register the events we want to track
CustomDPS.CustomDPSFrame:RegisterEvent("PLAYER_LOGIN");
CustomDPS.CustomDPSFrame:RegisterEvent("PLAYER_REGEN_DISABLED"); -- Enter combat
CustomDPS.CustomDPSFrame:RegisterEvent("PLAYER_REGEN_ENABLED"); -- Exit combat
CustomDPS.CustomDPSFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
CustomDPS.CustomDPSFrame:RegisterEvent("GROUP_ROSTER_UPDATE");
CustomDPS.CustomDPSFrame:RegisterEvent("GROUP_LEFT");

-- Event handler
CustomDPS.CustomDPSFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        self:initialize();
    elseif event == "PLAYER_REGEN_DISABLED" then
       self:enterCombat();
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:exitCombat();
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" and CustomDPS.inCombat then
        self:handleCombatEvent();
    end
end);

-- OnUpdate runs once per frame
CustomDPS.CustomDPSFrame:SetScript("OnUpdate", function(self, elapsed)
    if CustomDPS.inCombat then
        CustomDPS.timeBuffer = CustomDPS.timeBuffer + elapsed;
        while CustomDPS.timeBuffer > CustomDPS.updateInterval do
            self:updateDamageWindow();
            self:displayDPS();
            CustomDPS.timeBuffer = 0;
        end
    end
end);

function CustomDPS.CustomDPSFrame:initialize()
    CustomDPS.playerName = UnitName("player");
    self.MsgFrame:SetWidth(250);
    self.MsgFrame:SetHeight(75);
    self.MsgFrame:SetPoint("TOPLEFT", 200, -100);
    self.MsgFrame:SetFrameStrata("TOOLTIP");

    -- UI Backdrop
    self.MsgFrame:SetBackdrop(BACKDROP_TUTORIAL_16_16);

    -- UI Draggability
    self.MsgFrame:SetMovable(true);
    self.MsgFrame:EnableMouse(true);
    self.MsgFrame:RegisterForDrag("LeftButton");
    self.MsgFrame:SetScript("OnDragStart", function(self, button)
        self:StartMoving();
    end);
    self.MsgFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing();
    end);

    -- UI Resizing
    self.MsgFrame:SetResizable(true);
    self.MsgFrame:SetResizeBounds(250, 75, 250, 600);

    -- This makes the little triangle button used to resize
    local br = CreateFrame("Button", nil, self.MsgFrame);
    br:EnableMouse("true");
    br:SetPoint("BOTTOMRIGHT");
    br:SetSize(16,16);
    br:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down");
    br:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight");
    br:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up");
    br:SetScript("OnMouseDown", function(self)
        self:GetParent():StartSizing("BOTTOMRIGHT");
    end);
    br:SetScript("OnMouseUp", function(self)
        self:GetParent():StopMovingOrSizing("BOTTOMRIGHT");
    end);

    -- UI Text Component
    self:createDPSList();
end

-- Group

-- Group member structure
-- CustomDPS.party[partyMemberName]
-- CustomDPS.party[partyMemberName]["damageDuringWindow"]
-- CustomDPS.party[partyMemberName]["dps"]
-- CustomDPS.party[partyMemberName]["damageQueue"]
-- CustomDPS.party[partyMemberName]["damageQueueLength"]

function CustomDPS.CustomDPSFrame:initializeGroup()
    CustomDPS.party = {};
    self:initializeGroupMember(CustomDPS.playerName);
    self:handleGroupChange();
end

function CustomDPS.CustomDPSFrame:handleGroupChange()
    local partyInfo = GetHomePartyInfo();
    if partyInfo ~= nil then
        for k, v in pairs(partyInfo) do
            if CustomDPS.party[v] == nil then
                self:initializeGroupMember(v);
            end
        end
        self:displayDPS();
    end
end

function CustomDPS.CustomDPSFrame:initializeGroupMember(groupMemberName)
    CustomDPS.party[groupMemberName] = {};
    CustomDPS.party[groupMemberName]["damageBuffer"] = 0;
    CustomDPS.party[groupMemberName]["damageDuringWindow"] = 0;
    CustomDPS.party[groupMemberName]["damageQueue"] = CustomDPS.Queue.new();
    CustomDPS.party[groupMemberName]["damageQueueLength"] = 0;
    CustomDPS.party[groupMemberName]["dps"] = 0;
end

-- Combat

function CustomDPS.CustomDPSFrame:updateDamageWindow()
    -- Add damage buffer to damageWindow
    -- Check if damage queue is full
    --   not full: Increment queueLength
    --   full: Pop front, subtract popped from damageWindow
    -- Re-calculate DPS. (damageWindow / queueLength) is DPS over the window. Reset damage buffer

    for k, v in pairs(CustomDPS.party) do
        v["damageDuringWindow"] = v["damageDuringWindow"] + v["damageBuffer"];
        CustomDPS.Queue.pushright(v["damageQueue"], v["damageBuffer"]);
        -- queue gets one event a second, its length is equal to the amount of seconds the damage has been done over
        if v["damageQueueLength"] < CustomDPS.windowLengthInSeconds then
            v["damageQueueLength"] = v["damageQueueLength"] + 1;
        else
            local poppedValue = CustomDPS.Queue.popleft(v["damageQueue"]);
            v["damageDuringWindow"] = v["damageDuringWindow"] - poppedValue;
        end
        v["damageBuffer"] = 0;
        v["dps"] = math.floor(v["damageDuringWindow"] / v["damageQueueLength"]);
    end
end

function CustomDPS.CustomDPSFrame:handleCombatEvent()
    local timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo();
    -- If the damage has a source and that source is a party member
    if sourceName ~= nil and CustomDPS.party[sourceName] ~= nil then
        -- Do I want to do anything with other subevents? What about healing?
        -- Will want to also figure out how to handle events from other players, like tracking party member DPS and the party DPS as a whole
        if subevent == "SWING_DAMAGE" then
            local damageAmount = select(12, CombatLogGetCurrentEventInfo());
            CustomDPS.party[sourceName]["damageBuffer"] = CustomDPS.party[sourceName]["damageBuffer"] + damageAmount;
        elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" then
            local damageAmount = select(15, CombatLogGetCurrentEventInfo());
            CustomDPS.party[sourceName]["damageBuffer"] = CustomDPS.party[sourceName]["damageBuffer"] + damageAmount;
        end
    end
end

function CustomDPS.CustomDPSFrame:enterCombat()
    self:initializeGroup();
    CustomDPS.timeBuffer = 0;
    self:createDPSList();
    CustomDPS.inCombat = true;
end

function CustomDPS.CustomDPSFrame:exitCombat()
    CustomDPS.inCombat = false;
end

function CustomDPS.CustomDPSFrame:formattedDPS(playerName)
    return self:formatNumber(CustomDPS.party[playerName]["dps"]);
end

function CustomDPS.CustomDPSFrame:formatNumber(num)
    local numString = tostring(num);
    numString = string.reverse(numString);
    local finalizedString = "";
    local counter = 1;
    for c in numString:gmatch"." do
        if counter == 4 then
            finalizedString = finalizedString .. ","; 
            counter = 0;
        end
        finalizedString = finalizedString .. c;
        counter = counter + 1;
    end
    return string.reverse(finalizedString);
end

-- UI

function CustomDPS.CustomDPSFrame:displayDPS()
    -- Re-initialize the DPS list. Should I do something more efficient here?
    -- e.g. make all of these components when I enter combat and just update them every time displayDPS is called
    -- TODO: This should be ordered in most to least dps, maybe display the player character somewhere on its own?
    self:processPlayerDPS(CustomDPS.playerName, self:formattedDPS(CustomDPS.playerName));
    -- [playerName]["dps"]
    -- table.sort(CustomDPS.party, function(a, b) return a[2] > b[2] end)
    for k, v in pairs(CustomDPS.party) do
        local dpsListing = self:processPlayerDPS(k, self:formattedDPS(k));
    end
end

function CustomDPS.CustomDPSFrame:createDPSList()
    self.MsgFrame.dpsList = CreateFrame("Frame", nil, self.MsgFrame);
    -- self.MsgFrame.dpsList:SetPoint("TOPLEFT", 10, -10);
    self.MsgFrame.dpsList:SetPoint("CENTER", 0, 0);
    self.MsgFrame.dpsList:SetWidth(1);
    self.MsgFrame.dpsList:SetHeight(1);
    self.MsgFrame.dpsList.values = {};
end

function CustomDPS.CustomDPSFrame:processPlayerDPS(playerName, dps)
    local valueName = playerName .. "-dps";
    local dpsListing = nil;
    if self.MsgFrame.dpsList.values[valueName] ~= nil then
        dpsListing = self.MsgFrame.dpsList.values[valueName]
    else
        dpsListing = self.MsgFrame.dpsList:CreateFontString(valueName, "overlay", "GameFontNormal");
        dpsListing:SetPoint("RIGHT", 0, 0);
        dpsListing:SetJustifyH("LEFT");
        self.MsgFrame.dpsList.values[valueName] = dpsListing;
    end
    dpsListing:SetText(playerName .. "   " .. dps);
end
