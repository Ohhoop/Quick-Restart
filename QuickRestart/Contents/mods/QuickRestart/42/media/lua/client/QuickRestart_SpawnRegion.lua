QuickRestartSpawnRegion = QuickRestartSpawnRegion or {}
QuickRestartSpawnRegion._preparers = QuickRestartSpawnRegion._preparers or {}

function QuickRestartSpawnRegion.registerPreparer(fn)
    if type(fn) ~= "function" then
        return false
    end

    for _, existing in ipairs(QuickRestartSpawnRegion._preparers) do
        if existing == fn then
            return true
        end
    end

    QuickRestartSpawnRegion._preparers[#QuickRestartSpawnRegion._preparers + 1] = fn
    return true
end

function QuickRestartSpawnRegion.runPreparers(context)
    for _, preparer in ipairs(QuickRestartSpawnRegion._preparers) do
        local ok, result = pcall(preparer, context)
        if not ok then
            QuickRestartLog.warn("spawn region preparer failed error=" .. tostring(result))
        elseif type(result) == "string" and result ~= "" then
            return result
        end
    end

    return nil
end

function QuickRestartSpawnRegion.prepare(context, availableRegions)
    local preparedRegionName = QuickRestartSpawnRegion.runPreparers(context)
    if type(preparedRegionName) ~= "string" or preparedRegionName == "" then
        return nil, nil
    end

    local mapSpawnSelect = context.mapSpawnSelect
    local replacement = nil

    if mapSpawnSelect and mapSpawnSelect.listbox and type(mapSpawnSelect.listbox.items) == "table" then
        for index, entry in ipairs(mapSpawnSelect.listbox.items) do
            local region = entry.item and entry.item.region or nil
            if region and region.name == preparedRegionName then
                mapSpawnSelect.listbox.selected = index
                replacement = region
                break
            end
        end
    end

    if not replacement and type(availableRegions) == "table" then
        for _, region in ipairs(availableRegions) do
            if region and region.name == preparedRegionName then
                replacement = region
                break
            end
        end
    end

    if replacement and mapSpawnSelect then
        mapSpawnSelect.selectedRegion = replacement
    end

    return preparedRegionName, replacement
end

function QuickRestartSpawnRegion.describeRegions(regions)
    if type(regions) ~= "table" then
        return "<nil>"
    end

    local names = {}
    for _, region in ipairs(regions) do
        names[#names + 1] = tostring(region and region.name or nil)
    end
    return "[" .. table.concat(names, ", ") .. "]"
end

function QuickRestartSpawnRegion.describeListboxRegions(listbox)
    if type(listbox) ~= "table" or type(listbox.items) ~= "table" then
        return "<nil>"
    end

    local names = {}
    for _, entry in ipairs(listbox.items) do
        local region = entry and entry.item and entry.item.region or nil
        names[#names + 1] = tostring(region and region.name or nil)
    end
    return "[" .. table.concat(names, ", ") .. "]"
end

function QuickRestartSpawnRegion.resolve(args)
    local mapSpawnSelect = args.mapSpawnSelect
    local data = args.data
    local availableRegions = args.availableRegions

    local result = {
        selectedRegion = nil,
        source = nil,
        listboxIndex = nil,
        randomFellBack = false,
        preparedRegionName = nil,
        preparedApplied = false,
    }

    local selectedRegion = nil

    if args.wantRandomSpawn then
        if mapSpawnSelect.listbox and type(mapSpawnSelect.listbox.items) == "table"
            and #mapSpawnSelect.listbox.items > 0 then
            local randomIndex = ZombRand(#mapSpawnSelect.listbox.items) + 1
            local entry = mapSpawnSelect.listbox.items[randomIndex]
            local region = entry and entry.item and entry.item.region or nil
            if region and region.name then
                mapSpawnSelect.listbox.selected = randomIndex
                selectedRegion = region
                result.source = "random"
                result.listboxIndex = randomIndex
            end
        end

        if not selectedRegion and args.randomFallback then
            local region = QuickRestartRandomizer.pickRandomRegion(availableRegions)
            if region and region.name then
                selectedRegion = region
                result.source = "random"
            end
        end

        if selectedRegion then
            data.region = selectedRegion.name
        else
            result.randomFellBack = true
        end
    end

    if not selectedRegion and type(data.region) == "string" and data.region ~= ""
        and mapSpawnSelect.listbox and type(mapSpawnSelect.listbox.items) == "table" then
        for index, entry in ipairs(mapSpawnSelect.listbox.items) do
            local region = entry.item and entry.item.region or nil
            if region and region.name == data.region then
                mapSpawnSelect.listbox.selected = index
                selectedRegion = region
                result.source = "listbox"
                result.listboxIndex = index
                break
            end
        end
    end

    if not selectedRegion and type(data.region) == "string" and data.region ~= ""
        and type(availableRegions) == "table" then
        for _, region in ipairs(availableRegions) do
            if region and region.name == data.region then
                selectedRegion = region
                result.source = "available"
                break
            end
        end
    end

    if selectedRegion then
        mapSpawnSelect.selectedRegion = selectedRegion
    else
        selectedRegion = mapSpawnSelect:useDefaultSpawnRegion()
        result.source = "default"
    end

    local preparedRegionName, preparedRegion = QuickRestartSpawnRegion.prepare({
        data = data,
        mapSpawnSelect = mapSpawnSelect,
        sameWorld = args.sameWorld,
        regionName = selectedRegion and selectedRegion.name or nil,
    }, availableRegions)

    result.preparedRegionName = preparedRegionName
    if preparedRegionName and preparedRegion then
        selectedRegion = preparedRegion
        result.preparedApplied = true
    end

    result.selectedRegion = selectedRegion
    return result
end

return QuickRestartSpawnRegion
