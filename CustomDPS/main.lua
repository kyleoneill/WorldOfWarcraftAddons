-- Put everything in the addon inside a unique global table to avoid name collision
local CustomDPS = {};

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
        -- We have entered combat
       self:enterCombat();
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- We have exited combat
        self:exitCombat();
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" and CustomDPS.inCombat then
        self:handleCombatEvent();
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- TODO: The group change event also fires when people phase and unphase, leading to a lot of redundant calls
        -- I might to handle want more specific behavior, like "MEMBER_LEFT", "MEMBER_JOIN", "JOINED_GROUP"
        self:handleGroupChange();
    elseif event == "GROUP_LEFT" then
        self:handleLeaveGroup();
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

    -- Party info
    self:initializeGroup();

    -- UI Text
    self.MsgFrame.text = self.MsgFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    self.MsgFrame.text:SetPoint("TOPLEFT", 10, -10);
    self:displayDPS();
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
    end
end

function CustomDPS.CustomDPSFrame:handleLeaveGroup()
    self:initializeGroup();
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
    for k, v in pairs(CustomDPS.party) do
        self:initializeGroupMember(k);
    end
    CustomDPS.timeBuffer = 0;
    CustomDPS.inCombat = true;
end

function CustomDPS.CustomDPSFrame:exitCombat()
    CustomDPS.inCombat = false;
    self:setUIExitCombat();
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

function CustomDPS.CustomDPSFrame:setUIExitCombat()
    -- self.MsgFrame.text:SetText(CustomDPS.playerName .. " DPS last fight: " .. self:formattedDPS(CustomDPS.playerName));
end

function CustomDPS.CustomDPSFrame:setUIText(newText)
    self.MsgFrame.text:SetText(newText);
end

function CustomDPS.CustomDPSFrame:displayDPS()
    -- TODO: This should be ordered in most to least dps, maybe display the player character somewhere on its own?
    local stringBuilder = "";
    for k, v in pairs(CustomDPS.party) do
        stringBuilder = stringBuilder .. k .. " DPS: " .. self:formattedDPS(k) .. "\n";
    end
    self:setUIText(stringBuilder);
end

-- Queue

function CustomDPS.Queue.new()
    return {first = 0, last = -1}
end

function CustomDPS.Queue.pushleft (queue, value)
    local first = queue.first - 1
    queue.first = first
    queue[first] = value
end
  
function CustomDPS.Queue.pushright (queue, value)
    local last = queue.last + 1
    queue.last = last
    queue[last] = value
end

function CustomDPS.Queue.popleft (queue)
    local first = queue.first
    if first > queue.last then error("queue is empty") end
    local value = queue[first]
    queue[first] = nil        -- to allow garbage collection
    queue.first = first + 1
    return value
end

function CustomDPS.Queue.popright (queue)
    local last = queue.last
    if queue.first > last then error("queue is empty") end
    local value = queue[last]
    queue[last] = nil         -- to allow garbage collection
    queue.last = last - 1
    return value
end

-- Other Misc

function dumpTable(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. dumpTable(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
 end
 

-- Misc function I wrote to learn
function printMoney()
    gold = 0;
    silver = 0;
    copper = 0;
    currentMoneyInCopper = GetMoney();
    if currentMoneyInCopper > 10000 then
        gold = math.floor(currentMoneyInCopper / 10000);
        temp = gold * 10000;
        currentMoneyInCopper = currentMoneyInCopper - temp;
    end
    if currentMoneyInCopper > 100 then
        silver = math.floor(currentMoneyInCopper / 100);
        temp = silver * 100;
        currentMoneyInCopper = currentMoneyInCopper - temp;
    end
    print('Gold: ' .. gold .. '\n' .. 'Silver: ' .. silver .. '\n' .. 'Copper: ' .. currentMoneyInCopper);
end
