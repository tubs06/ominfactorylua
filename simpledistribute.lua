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
local distributeAmmount = 0

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

    -- (3) Get ammount to distribute
    print("Enter ammount to distribute: ")
    distributeAmmount = tonumber(read())

    -- (4) Save config
    local fileHandle = fs.open("/cfg", "w")

    toSave = {
        outputChestsCount,
        outputChests,
        inputChestName,
        distributeAmmount
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
    distributeAmmount = config[4]
	
	print("Config loaded from /cfg")
end

-- input chest object
local inputChest = peripheral.wrap(inputChestName)

-- current chest counter
local currentChest = 1

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

function findAndDisperseCombo(chest)
    -- get chest dictionary
    local chestDict = getChestDictionary(chest)
    
    -- iterate over chest dictionary, if ammount of items is greater than disperse ammount then disperse max possible
    for dictKey, item in pairs(chestDict) do
        -- if we have enough
        if item[1][1] >= distributeAmmount then
            -- calculate and set ammount to disperse
            local maxPossible = math.floor(item[1][1] / distributeAmmount)

            -- distribute
            for iteration=1, maxPossible, 1 do
                print("Dispersion iteration "..iteration)

                --print("Must disperse "..distributeAmmount)
                local toDisperse = distributeAmmount
                for currentSlotIndex = item[1][2] - 1, 2, -1 do
                    --os.sleep(5)
                    -- get current slot
                    local currentSlot = item[currentSlotIndex]
                    --print("Checking slot "..currentSlot[1].." with "..currentSlot[2].." items")
                    
                    -- if ammount needed is contained in this slot, disperse and update ammount
                    if toDisperse < currentSlot[2] then
                        --print("Slot has more than needed")
                        inputChest.pushItems(outputChests[currentChest], currentSlot[1], toDisperse)
                        item[currentSlotIndex][2] = item[currentSlotIndex][2] - toDisperse
                        --print("Moving "..toDisperse.." items to chest and going to next iteration")
                        break
                    -- ammount needed is excatly whats in slot
                    elseif toDisperse == currentSlot[2] then
                        --print("Slot has exactly whats needed")
                        inputChest.pushItems(outputChests[currentChest], currentSlot[1], toDisperse)
                        -- remove slot
                        table.remove(item, currentSlotIndex)
                        item[1][2] = item[1][2] - 1
                        --print("Moving "..toDisperse.." items to chest and going to next iteration")
                        break
                    -- not enough in slot
                    else
                        --print("Slot has less than whats needed")
                        inputChest.pushItems(outputChests[currentChest], currentSlot[1], currentSlot[2])

                        toDisperse = toDisperse - currentSlot[2]
                        -- remove slot
                        table.remove(item, currentSlotIndex)
                        item[1][2] = item[1][2] - 1
                        --print("Moving "..currentSlot[2].." items to chest and going to next slot")
                    end
                end

                --print("Incrementing chest counter")
                currentChest = (currentChest % outputChestsCount) + 1
            end
        end
    end

    return nil
end

while true do
    if next(inputChest.list()) ~= nil then
        local report = findAndDisperseCombo(inputChest)
    end
    os.sleep(1)
end
