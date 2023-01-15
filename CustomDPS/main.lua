-- Put everything in the addon inside a unique global table to avoid name collision
local CustomDPS = {};
CustomDPS.Queue = {};

-- Global variables
CustomDPS.damageBuffer = 0;
CustomDPS.timeBuffer = 0;
CustomDPS.totalTimeForFight = 0;
CustomDPS.inCombat = false;
CustomDPS.updateInterval = 1;
CustomDPS.playerName = nil;

-- Frames to contain addon functions
CustomDPS.CustomDPSFrame = CreateFrame("Frame", "CustomDPSFrame");
CustomDPS.CustomDPSFrame.MsgFrame = CreateFrame("Frame", nil, UIParent);

-- Register the events we want to track
CustomDPS.CustomDPSFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
CustomDPS.CustomDPSFrame:RegisterEvent("PLAYER_LOGIN");
CustomDPS.CustomDPSFrame:RegisterEvent("PLAYER_REGEN_DISABLED"); -- Enter combat
CustomDPS.CustomDPSFrame:RegisterEvent("PLAYER_REGEN_ENABLED"); -- Exit combat
CustomDPS.CustomDPSFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");

-- Event handler
CustomDPS.CustomDPSFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        CustomDPS.CustomDPSFrame:initialize();
    elseif event == "PLAYER_ENTERING_WORLD" then
        CustomDPS.playerName = UnitName("player");
        CustomDPS.CustomDPSFrame:setUIText(CustomDPS.playerName .. " DPS: 0");
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- We have entered combat
        CustomDPS.CustomDPSFrame:enterCombat();
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- We have exited combat
        CustomDPS.CustomDPSFrame:exitCombat();
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" and CustomDPS.inCombat == true then
        CustomDPS.CustomDPSFrame:handleCombatEvent();
    end
end);

-- OnUpdate runs once per frame
CustomDPS.CustomDPSFrame:SetScript("OnUpdate", function(self, elapsed)
    if CustomDPS.inCombat then
        CustomDPS.timeBuffer = CustomDPS.timeBuffer + elapsed;
        CustomDPS.totalTimeForFight = CustomDPS.totalTimeForFight + elapsed;
        while CustomDPS.timeBuffer > CustomDPS.updateInterval do
            self:displayDPS();
            CustomDPS.timeBuffer = 0;
        end
    end
end);

function CustomDPS.CustomDPSFrame:initialize()
    self.MsgFrame:SetWidth(100);
    self.MsgFrame:SetHeight(100);
    self.MsgFrame:SetPoint("TOPLEFT", 200, -100);
    self.MsgFrame:SetFrameStrata("TOOLTIP");
    self.MsgFrame.text = self.MsgFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    self.MsgFrame.text:SetPoint("CENTER");
end

-- Combat

function CustomDPS.CustomDPSFrame:handleCombatEvent()
    local timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo();
    if sourceName ~= nil and sourceName == CustomDPS.playerName then
        -- Do I want to do anything with other subevents? What about healing?
        -- Will want to also figure out how to handle events from other players, like tracking party member DPS and the party DPS as a whole
        if subevent == "SWING_DAMAGE" then
            local damageAmount = select(12, CombatLogGetCurrentEventInfo());
            CustomDPS.damageBuffer = CustomDPS.damageBuffer + damageAmount;
        elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" then
            local damageAmount = select(15, CombatLogGetCurrentEventInfo());
            CustomDPS.damageBuffer = CustomDPS.damageBuffer + damageAmount;
        end
    end
end

function CustomDPS.CustomDPSFrame:displayDPS()
    -- Need a way to smooth this
    --   1. Keep a running time of damage and time for a fight. DPS is damage/time. This will cause DPS to become stagnant and not change during a long fight though
    --   2. Every update add a data-frame to a queue. When the queue is at 60, add one and pop one. Calculate the DPS by
    --      averaging the damage from each event (events can be nil if there was no damage event in a given update) divided by the size of the buffer (like 60)
    -- Currently doing 1, 2 would be a lot smoother. Would also use a lot more resources in large parties if I do that for each member? How
    -- do I do that efficiently?

    local dps = CustomDPS.CustomDPSFrame:formattedDPS();
    local totalDamage = CustomDPS.CustomDPSFrame:formatNumber(CustomDPS.damageBuffer);
    self:setUIText(CustomDPS.playerName .. " DPS: " .. dps .. "\n" .. CustomDPS.playerName .. " total damage: " .. totalDamage);
end

function CustomDPS.CustomDPSFrame:enterCombat()
    CustomDPS.damageBuffer = 0;
    CustomDPS.timeBuffer = 0;
    CustomDPS.totalTimeForFight = 0;
    CustomDPS.inCombat = true;
end

function CustomDPS.CustomDPSFrame:exitCombat()
    CustomDPS.timeBuffer = 0;
    CustomDPS.inCombat = false;
    CustomDPS.CustomDPSFrame:setUIExitCombat();
end

function CustomDPS.CustomDPSFrame:calculateDPS()
    return math.floor(CustomDPS.damageBuffer / CustomDPS.totalTimeForFight);
end

function CustomDPS.CustomDPSFrame:formattedDPS()
    local dps = CustomDPS.CustomDPSFrame:calculateDPS();
    return CustomDPS.CustomDPSFrame:formatNumber(dps);
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
    local dps = CustomDPS.CustomDPSFrame:formattedDPS();
    self.MsgFrame.text:SetText(CustomDPS.playerName .. " DPS last fight: " .. dps);
end

function CustomDPS.CustomDPSFrame:setUIText(newText)
    self.MsgFrame.text:SetText(newText);
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
