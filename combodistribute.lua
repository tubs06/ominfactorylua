-- TABLE FUNCTIONS
function table.contains(table, element)
    for key, value in pairs(table) do
      if value == element then
        return true, key
      end
    end
    return false, -1
end
  
function table.removeItem(tableIn, element)
	for key, value in pairs(tableIn) do
		if value == element then
			table.remove(tableIn, key)
			return true;
		end
	end
	return false
end

-- END OF FUNCTIONS

-- MAIN PROGRAM

-- Chest Variables
local outputChests = { }
local outputChestsIndex = 1
local outputChestsCount = 0
local inputChestName = ""

-- Modem Variables
local modemSide = ""
local protocol = ""

-- Starting point, if config not present
if fs.exists("/cfg") == false then
    -- (1) Detect chests connected to network
    for _, value in pairs(peripheral.getNames()) do
        if string.find(value, "minecraft:chest") then
            outputChests[outputChestsIndex] = value
            outputChestsIndex = outputChestsIndex + 1
        end
    end

     -- (2) Print connected chests and ask user to define input chest
    if outputChestsIndex ~= 1 then
        print(("Detected %d chests as follows:"):format(outputChestsIndex - 1))
        for _, value in pairs(outputChests) do
            print(value)
        end

        while true do
            print("Please enter number corresponding to input chest:")
            local input = tonumber(read())
            local exitLoop = false
            for _, value in pairs(outputChests) do
                if tonumber(string.sub(value, 17, -1)) == input then
                    -- This chest is now defined as the input chest, remove from outputChests table
                    table.removeItem(outputChests, value)
                    outputChestsIndex = outputChestsIndex - 1
                    -- Assign as input chest
                    inputChestName = value
                    exitLoop = true
                    break
                end
            end
            if exitLoop then
                break
            end
            print("Number not present, try again")
        end
    else
        error("No chests connected to computer via modem")
    end

    outputChestsCount = outputChestsIndex - 1

    -- (3) Get wireless modem side from user
    while true do
        print("Please enter side of wireless modem:")
        modemSide = read()
        if peripheral.isPresent( modemSide ) and peripheral.getType( modemSide ) == "modem" then
            break
        end
        print("Modem not detected on "..modemSide.." side.")
    end


    -- (4) Get protocol from user
    print("Enter protocol: ")
    protocol = read()

    -- (5) Save config
    local fileHandle = fs.open("/cfg", "w")

    toSave = {
        outputChestsCount,
        outputChests,
        inputChestName,
        modemSide,
        protocol
    }

    fileHandle.write(textutils.serialise(toSave))
    fileHandle.close()

    print("Config saved to /cfg. Starting up")
else
    -- cfg exists, load it
    local fileHandle = fs.open("/cfg", "r")
    local data = fileHandle.readAll()
    fileHandle.close()
    local config = textutils.unserialise(data)

    outputChestsCount = config[1]
    outputChests = config[2]
    inputChestName = config[3]
    modemSide = config[4]
    protocol = config[5]
	
	print("Config loaded from /cfg")
end

-- input chest object
local inputChest = peripheral.wrap(inputChestName)

-- current chest counter
local currentChest = 1

-- retrieve combos from protocol
rednet.open(modemSide)
print("Waiting for combo table on protocol " .. protocol)
senderId, combos, distance = rednet.receive(protocol)
print("Recieved combo table succesfully. Starting.")
rednet.close(modemSide)

-- CHEST FUNCTIONS

function getChestDictionary(chest)
    local chestDict = { }
    for slot, item in pairs(chest.list()) do
        local dictKey = item.name..tostring(item.damage)
        if chestDict[dictKey] == nil then
            chestDict[dictKey] = { { item.count, 3 }, { slot, item.count } }
        else
            local nextSlot = chestDict[dictKey][1][2]
            -- increment count
            chestDict[dictKey][1][1] = chestDict[dictKey][1][1] + item.count
            -- add next slot
            chestDict[dictKey][nextSlot] = { slot, item.count }
            -- increment next slot
            chestDict[dictKey][1][2] = nextSlot + 1
        end
    end
    return chestDict
end

function findCombo(chest)
    -- get chest dictionary
    local chestDict = getChestDictionary(chest)
    --print(textutils.serialise(chestDict))


    -- iterate over every combo
    for comboId, combo in pairs(combos) do
        --print("Trying combo "..comboId)
        -- define variable for checking for a full combo
        local fullCombo = true

        -- define report variable
        local report = { comboId, 1000, { } } -- (comboId, maxPossible)


        for itemId, item in pairs(combo) do
            --print("Trying item "..itemId)
            -- extract item from dictionary
            
            local dictItem = chestDict[item[1]..tostring(item[2])]
            --print(textutils.serialise(dictItem))

            -- if item exists in inventory.
            if dictItem ~= nil then
                -- if enough of item is present
                if dictItem[1][1] >= item[3] then
                    -- JUST calculate max we could make with the ammount present, update absolute max variable
                    local maxPossibleFromCurrentItem = math.floor(dictItem[1][1] / item[3])
                    if maxPossibleFromCurrentItem < report[2] then
                        report[2] = maxPossibleFromCurrentItem
                    end

                    local nextSlot = dictItem[1][2] - 2
                    local slotsCopy = textutils.unserialise(textutils.serialise(dictItem))
                    table.remove(slotsCopy, 1)
                    -- add item slot info to report
                    report[3][itemId] = { nextSlot, slotsCopy }
                -- else, not enough of item is present, go to next combo.
                else
                    --print("Not enough of item "..itemId)
                    fullCombo = false
                    break
                end
            -- else, item doesnt exist in inventory. go to next combo.
            else
                -- do something here to make sure no future combos with this item is used (not present in inventory)
                --print("Item "..itemId.." not present")
                fullCombo = false
                break
            end
            -- If we got here and are on last item, we have a full valid combo. Send report
        end

        if fullCombo then
            return report
        end
    end
    return nil
end


function disperseCombo(chest, report)
    --print("Entered dispersion phase")
    -- iterate over the number to disperese as calculated in the find combo function
    for iteration=1, report[2], 1 do
       print("Dispersion iteration "..iteration)
        -- iterate over each item in the combo and disperse to the current output
        for itemId, itemInfo in pairs(report[3]) do
            -- get the ammount to disperse to this output
            local toDisperse = combos[report[1]][itemId][3]
            --print("Attempting to disperse "..toDisperse.." of item "..itemId.." ("..combos[report[1]][itemId][1]..")")
            -- for every slot in the item info, go backwards adding until we have enough
            for currentSlotIndex = itemInfo[1], 1, -1 do
                -- get current slot
                local currentSlot = itemInfo[2][currentSlotIndex]

                -- if ammount needed is contained in this slot, disperse and UPDATE AMMOUNT IN REPORT
                if toDisperse < currentSlot[2] then
                    --print("Slot "..currentSlot[1].." has more than needed.")
                    -- disperse items
                    print("Dispersing "..toDisperse.." of "..combos[report[1]][itemId][1].." from slot "..currentSlot[1])
                    inputChest.pushItems(outputChests[currentChest], currentSlot[1], toDisperse)
                    -- update ammount of item in this slot in report
                    report[3][itemId][2][currentSlotIndex][2] = report[3][itemId][2][currentSlotIndex][2] - toDisperse
                    -- go to next item
                    break
                elseif toDisperse == currentSlot[2] then
                    --print("Slot "..currentSlot[1].." has exactly whats needed.")
                    -- disperse items
                    print("Dispersing "..toDisperse.." of "..combos[report[1]][itemId][1].." from slot "..currentSlot[1])
                    inputChest.pushItems(outputChests[currentChest], currentSlot[1], toDisperse)
                    -- decrement currentSlot counter
                    report[3][itemId][1] = report[3][itemId][1] - 1
                    -- remove slot from report for next iteration
                    table.remove(report[3][itemId][2], currentSlotIndex)
                    -- go to next item
                    break
                -- else, ammount needed is not contained in this slot. push everything from this slot, delete this slot and move to next slot
                else
                    --print("Slot "..currentSlot[1].." has less than whats needed.")
                    -- disperse all items in slot
                    print("Dispersing "..toDisperse.." of "..combos[report[1]][itemId][1].." from slot "..currentSlot[1])
                    inputChest.pushItems(outputChests[currentChest], currentSlot[1], currentSlot[2])
                    -- update ammount to disperse
                    toDisperse = toDisperse - currentSlot[2]
                    -- decrement currentSlot counter
                    report[3][itemId][1] = report[3][itemId][1] - 1
                    -- remove slot for next iteration
                    table.remove(report[3][itemId][2], currentSlotIndex)
                    -- continue onto next slot
                end
            end
        end
        -- increment currentChest to next chest
        --print(currentChest)
        currentChest = (currentChest % outputChestsCount) + 1
    end
end

-- END CHEST FUNCTIONS
-- Item distribution test code
--[[
for i=1, outputChestsCount, 1 do
    inputChest.pushItems(outputChests[i], 1, 1)
end
--]]

-- iterate over combos like we did before


while true do
    if next(inputChest.list()) ~= nil then
        --print("Looking for combos.")
        local report = findCombo(inputChest)
        if report ~= nil then
            --print(report[2].."x of combo "..report[1].." found.")
            disperseCombo(inputChest, report)
        end
    end
    os.sleep(1)
end
