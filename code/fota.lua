# LuatOS Air780EG FUFU FOTA (Firmware Over-The-Air)
-- FOTA update support using LuatOS OTA server

-- Configuration
-- Make sure PRODUCT_KEY is set in projectConfig.lua or .env
-- Register your product at iot.openluat.com to enable FOTA

local M = {}

-- Check for firmware update
function M.check_update()
    -- Check if we have a valid product key
    if not _G.PRODUCT_KEY or _G.PRODUCT_KEY == "YOUR_64_CHARACTER_PRODUCT_KEY_HERE" then
        log.info("FOTA", "No product key configured, skipping FOTA check")
        return false
    end
    
    -- LuatOS OTA check
    -- This uses the built-in ota API
    local ok, err = pcall(function()
        -- ota.check() - checks for updates on OTA server
        -- Returns: true/false, version string, or error
        local result = ota.check()
        if result then
            log.info("FOTA", "Update available:", result)
            return true
        else
            log.info("FOTA", "No update available")
            return false
        end
    end)
    
    if not ok then
        log.info("FOTA", "FOTA check error:", err)
    end
    
    return ok
end

-- Download and install firmware update
function M.download_and_install()
    if not _G.PRODUCT_KEY then
        log.info("FOTA", "No product key, cannot download FOTA")
        return false
    end
    
    log.info("FOTA", "Starting FOTA download...")
    
    -- Start FOTA download
    -- This will download the firmware package from OTA server
    local ok, err = pcall(function()
        ota.install()
    end)
    
    if ok then
        log.info("FOTA", "FOTA update completed, device will restart")
        -- Device will automatically restart after OTA install
        return true
    else
        log.info("FOTA", "FOTA update failed:", err)
        return false
    end
end

-- Get current firmware version
function M.get_current_version()
    -- Try to get version from system
    local version = _G.VERSION or "unknown"
    -- Can also check sys.info() for more details
    local sys_info = sys.info()
    if sys_info and sys_info.work_version then
        version = sys_info.work_version
    end
    return version
end

-- Main FOTA check function (call periodically)
function M.periodic_check()
    -- Check for updates every N minutes/hours
    -- Can be called from main loop or scheduled task
    local current_version = M.get_current_version()
    log.info("FOTA", "Current version:", current_version)
    
    if M.check_update() then
        -- Optionally ask user or auto-download
        -- For trackers, maybe auto-download during idle time
        log.info("FOTA", "Update found, initiating download...")
        M.download_and_install()
    else
        log.info("FOTA", "No update at this time")
    end
end

-- Initialize FOTA support
function M.init()
    log.info("FOTA", "FOTA support initialized")
    log.info("FOTA", "Product Key:", _G.PRODUCT_KEY)
    log.info("FOTA", "Current Version:", M.get_current_version())
    
    -- Perform initial check
    M.check_update()
end

return M