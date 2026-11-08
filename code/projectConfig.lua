# LuatOS Air780EG FUFU Project Configuration
-- Project configuration loaded from .env file

-- Load environment variables
local loadenv = require("loadenv")
loadenv.load(".env")

-- Product key for FOTA and identification
-- Register at iot.openluat.com to get your product key
_G.PRODUCT_KEY = _G.PRODUCT_KEY or "YOUR_64_CHARACTER_PRODUCT_KEY_HERE"

-- Software version
_G.VERSION = _G.VERSION or "1.0.0"

-- MQTT Configuration (overridden by .env if present)
_G.MQTT_BROKER = _G.MQTT_BROKER or "mqtt.openluat.com"
_G.MQTT_PORT = tonumber(_G.MQTT_PORT) or 1883
_G.MQTT_CLIENT_ID = _G.MQTT_CLIENT_ID or "fufu_air780eg_device"
_G.MQTT_USERNAME = _G.MQTT_USERNAME or ""
_G.MQTT_PASSWORD = _G.MQTT_PASSWORD or ""
_G.MQTT_TOPIC = _G.MQTT_TOPIC or "tracker/position"
_G.MQTT_KEEPALIVE = tonumber(_G.MQTT_KEEPALIVE) or 60

-- Network settings
-- APN for your carrier (uncomment and modify if needed)
-- _G.APN = "your.apn.name"
-- _G.APN_USER = "your APN username"
-- _G.APN_PASSWORD = "your APN password"

-- GNSS configuration
-- Default satellite mode: GPS+Beidou (11), can be changed via uart command
-- Mode 11: GPS+Beidou (default)
-- Mode 01: GPS L1 SBAS QZSS
-- Mode 10: Beidou only
-- To configure: uart.write(1, "$CFGSYS,H11\r\n") sys.wait(20)

-- Tracking settings
-- Position report interval in milliseconds
_G.POSITION_INTERVAL = tonumber(_G.POSITION_INTERVAL) or 10000  -- 10 seconds

-- MQTT report interval
_G.MQTT_REPORT_INTERVAL = tonumber(_G.MQTT_REPORT_INTERVAL) or 10000  -- 10 seconds

-- Debug level
-- 0 = none, 1 = errors, 2 = warnings, 3 = info, 4 = debug
_G.DEBUG_LEVEL = tonumber(_G.DEBUG_LEVEL) or 3

log.info("CONFIG_LOADED", "Product Key:", string.sub(_G.PRODUCT_KEY, 1, 8) .. "...")
log.info("CONFIG_LOADED", "Version:", _G.VERSION)
log.info("CONFIG_LOADED", "MQTT Broker:", _G.MQTT_BROKER)
log.info("CONFIG_LOADED", "Position Interval:", _G.POSITION_INTERVAL, "ms")

-- Verify product key is configured
if _G.PRODUCT_KEY == "YOUR_64_CHARACTER_PRODUCT_KEY_HERE" then
    log.warn("CONFIG", "Please set your PRODUCT_KEY in .env or projectConfig.lua")
end