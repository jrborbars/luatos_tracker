-- projectConfig.lua - tracker configuration for the FUFU Air780EG dongle
-- Order of precedence: /luadb/.env (or .env)  >  built-in defaults below.
-- Loaded with require("projectConfig"); returns a typed table, and keeps the
-- _G.* copies too so older code that reads globals still works.

local loadenv = require("loadenv")

-- 1. Pull KEY=VALUE strings from the flashed .env file (if any).
-- LUATOS_ENV_FILE is a test hook used by tools/sim.lua, unset in production.
loadenv.load(_G.LUATOS_ENV_FILE)

-- 2. Helpers: convert and apply defaults
local function num(key, default)
    local value = tonumber(_G[key])
    if not value then
        value = default
    end
    _G[key] = value
    return value
end

local function str(key, default)
    local value = _G[key]
    if value == nil or value == "" then
        value = default
    end
    _G[key] = value
    return value
end

local function clamp(value, min, max)
    if value < min then
        return min
    end
    if value > max then
        return max
    end
    return value
end

local function bool(key, default)
    local value = _G[key]
    if value == nil or value == "" then
        return default
    end
    value = tostring(value):lower()
    return value == "1" or value == "true" or value == "yes" or value == "on"
end

-- 3. Product key / version (required by FOTA on iot.openluat.com)
_G.PRODUCT_KEY = _G.PRODUCT_KEY or "YOUR_64_CHARACTER_PRODUCT_KEY_HERE"
-- iot.openluat.com requires the XXX.YYY.ZZZ layout, three digits per group
_G.VERSION = _G.VERSION or "001.000.000"

-- 4. Typed configuration table
local cfg = {
    PRODUCT_KEY = _G.PRODUCT_KEY,
    VERSION = _G.VERSION,

    -- MQTT
    MQTT_BROKER = str("MQTT_BROKER", "mqtt.openluat.com"),
    MQTT_PORT = num("MQTT_PORT", 1883),
    -- EMQX Cloud and most brokers use a TLS port; mqtt.create(ssl=true)
    -- encrypts without certificate verification, which is enough here.
    MQTT_SSL = bool("MQTT_SSL", num("MQTT_PORT", 1883) == 8883 or num("MQTT_PORT", 1883) == 8884),
    MQTT_CLIENT_ID = _G.MQTT_CLIENT_ID or "", -- empty means "use the IMEI"
    MQTT_USERNAME = _G.MQTT_USERNAME or "",
    MQTT_PASSWORD = _G.MQTT_PASSWORD or "",
    MQTT_TOPIC = str("MQTT_TOPIC", "tracker/position"),
    -- libemqtt clamps keepalive into 15..600 seconds anyway
    MQTT_KEEPALIVE = clamp(num("MQTT_KEEPALIVE", 240), 15, 600),
    MQTT_RECONNECT_MS = num("MQTT_RECONNECT_MS", 5000),
    MQTT_QOS = num("MQTT_QOS", 1),

    -- GNSS: the internal GPS+Beidou receiver of the Air780E family sits on uart2
    GNSS_UART = num("GNSS_UART", 2),
    GNSS_BAUD = num("GNSS_BAUD", 115200),
    GNSS_DEBUG = (_G.GNSS_DEBUG == "1" or _G.GNSS_DEBUG == "true"),

    -- Reporting
    POSITION_INTERVAL = num("POSITION_INTERVAL", 10000),   -- ms between samples
    HEARTBEAT_INTERVAL = num("HEARTBEAT_INTERVAL", 60000), -- ms between repeats when stationary
    NET_TIMEOUT = num("NET_TIMEOUT", 60000),               -- ms to wait for a cellular IP

    -- Logging: SILENT / DEBUG / INFO / WARN / ERROR / FATAL
    LOG_LEVEL = _G.LOG_LEVEL or "INFO",
}

-- 5. Startup summary (never log the password)
log.info("CONFIG", "project", PROJECT, "version", cfg.VERSION)
log.info("CONFIG", "mqtt", cfg.MQTT_BROKER .. ":" .. cfg.MQTT_PORT,
    cfg.MQTT_SSL and "(tls)" or "(plain)", "topic", cfg.MQTT_TOPIC)
log.info("CONFIG", "gnss uart", cfg.GNSS_UART, cfg.GNSS_BAUD)
log.info("CONFIG", "position interval", cfg.POSITION_INTERVAL, "ms")

if cfg.PRODUCT_KEY == "YOUR_64_CHARACTER_PRODUCT_KEY_HERE" then
    log.warn("CONFIG", "PRODUCT_KEY not set, FOTA disabled (set it in .env)")
end

return cfg
