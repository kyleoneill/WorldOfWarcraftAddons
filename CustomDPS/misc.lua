-- Misc

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
