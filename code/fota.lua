-- fota.lua - remote update for the tracker (firmware + script) via libfota2
-- Real API: libfota2.request(cbFnc, opts) - the callback comes first, and
-- opts.project_key defaults to the global PRODUCT_KEY. There is no ota.check()
-- and no ota.install() in LuatOS.

local M = { available = false }

local PLACEHOLDER = "YOUR_64_CHARACTER_PRODUCT_KEY_HERE"

local ok, libfota2 = pcall(require, "libfota2")
if ok and libfota2 then
    M.lib = libfota2
    M.available = true
end

local RESULT_TEXT = {
    [0] = "success, rebooting",
    [1] = "connection failed, check url or server",
    [2] = "url error",
    [3] = "server closed the connection",
    [4] = "bad response body: empty package, 4xx/5xx, or already up to date",
    [5] = "PRODUCT_KEY missing, or VERSION is not XXX.YYY.ZZZ",
}

local function network_ready()
    if socket and socket.adapter then
        return socket.adapter() and true or false
    end
    return false
end

-- Reference implementation of the result callback (0..5)
function M.on_result(ret)
    log.info("FOTA", "result", ret, RESULT_TEXT[ret] or "unknown")
    if ret == 0 then
        log.info("FOTA", "download finished, rebooting to install")
        rtos.reboot()
    end
end

-- Single update check. Returns false when the check cannot even start.
function M.check(timeout_ms)
    if not M.available then
        log.info("FOTA", "libfota2 not in this build, skipped")
        return false
    end
    if not _G.PRODUCT_KEY or _G.PRODUCT_KEY == PLACEHOLDER then
        log.info("FOTA", "PRODUCT_KEY not configured, skipped")
        return false
    end
    if not network_ready() then
        log.info("FOTA", "network not ready, skipped")
        return false
    end

    log.info("FOTA", "checking, current version", _G.VERSION)
    local started, err = pcall(M.lib.request, M.on_result, {
        project_key = _G.PRODUCT_KEY,
        timeout = timeout_ms or 120000, -- library default is 300000 ms
    })
    if not started then
        log.error("FOTA", "request failed", err)
        return false
    end
    return true
end

-- Periodic check; default is every 6 hours
function M.auto_check(interval_ms)
    if not M.available then
        return
    end
    local interval = interval_ms or 6 * 3600 * 1000
    sys.taskInit(function()
        sys.wait(interval)
        while true do
            M.check()
            sys.wait(interval)
        end
    end)
end

function M.version()
    return _G.VERSION or "unknown"
end

return M
