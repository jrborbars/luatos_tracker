# LuatOS Air780EG Tracker System - FUFU Dongle Project Plan

## Overview
Tracker using FUFU Air780EG USB dongle (NDIS/USB mode) for outdoor IoT positioning.

## Hardware Platform
### FUFU Air780EG USB Dongle
- Form factor: Compact "pendrive" style USB dongle
- Connectivity: NDIS/USB plug-and-play mode (no drivers needed)
- Cellular: 4G Cat.1 LTE (automatic network registration after SIM + USB)
- GNSS: Integrated or external antenna (varies by specific model)
- Power: Bus-powered from USB host (5V, regulated on board)
- SIM: Nano SIM card slot required
- Boot: Plug into USB host (no external PWR key needed)
- OS recognition: Appears as network interface (NDIS), not serial port

## Critical Notes (FUFU Dongle Specific)

### USB NDIS Mode (Critical)
- Network works via NDIS/USB, NOT UART AT commands
- net.isready() checks NDIS status
- net.get_ipaddr() returns IP when connected
- May need sys.wait(5000) after USB plug for NDIS initialization
- SIM must be inserted before/when plugging in USB

### GNSS Antenna Variance
- Check specific FUFU model: integrated antenna or u.FL connector?
- If integrated: may work immediately outdoors
- If external: same 50 matching rules apply
- GNSS_VCC: Still 3.3V for active antenna (verify on specific model)
- Some FUFU models may have no external antenna connector

### Power Source
- FUFU: Powered via USB host (5V, regulated on board)
- No external PWR key - plugging in powers up
- LED indicator behavior may differ from dev board

### Debug & Flashing
- USB connection for LuaTools firmware upload
- Check luatools -l for available ports (may change between sessions)
- SIM must be inserted for most operations
- May appear as different device name each time plugging in
- Network must be established before some FOTA operations

## Software Requirements
- LuatOS firmware V1124 for full Air780EG support
- GNSS library: gns API
- Network: net library (NDIS/USB mode, not UART AT)
- MQTT/HTTP: For IoT platform data transmission
- LuaTools: For firmware flashing via USB

## File Structure
```
luatos_tracker/code/main.lua
luatos_tracker/code/projectConfig.lua
luatos_tracker/code/fota.lua
```

## Minimal main.lua (FUFU Version)
```lua
log.info("FUFU_TEST", "Starting FUFU Air780EG test")
sys.wait(5000) -- Wait for NDIS initialization

-- Check network status
if net.isready() then
    local ip = net.get_ipaddr()
    log.info("NET_READY", "IP:", ip)
else
    log.info("NET_WAIT", "Waiting for NDIS connection...")
end

-- GNSS test
local lat, lon = gps.latitude(), gps.longitude()
if lat then
    log.info("GNSS_FIX", "Position:", lat, lon)
else
    log.info("GNSS_WAIT", "Go outdoors for GNSS fix")
end

-- Main tracking loop
while true do
    local lat, lon = gps.latitude(), gps.longitude()
    if lat then log.info("POSITION", lat, lon) end
    sys.sleep(2000)
end
```

## GNSS Configuration
- Default satellite mode: GPS+Beidou (Mode 11)
- Positioning rate: 1Hz default (configurable via $CFGNAV command)
- AGNSS: Assisted GNSS available when connected to cellular

## Power Management
- GNSS draws current even when idle
- Use gps.close() for standby mode (~500uA)
- USB power limited (consider external power for continuous tracking)

## Antenna Design
- Check specific FUFU model for antenna type
- 50Ohm impedance matching if external antenna
- Keep lines short for GNSS transmission
- GNSS_VCC provides 3.3V for active antenna (verify on model)

## Development Workflow
1. Insert Nano SIM card
2. Plug FUFU dongle into USB host
3. Wait 5-10s for NDIS initialization
4. Test network: net.isready(), net.get_ipaddr()
5. Test GNSS: gps.latitude/longitude() (outdoor recommended)
6. Run tracking loop, send position to IoT platform
7. FOTA: Configure PRODUCT_KEY in projectConfig.lua, use LuaTools for updates

## Testing Checklist
- [ ] Nano SIM card inserted
- [ ] Plugged into USB host
- [ ] Wait 5-10s for NDIS init
- [ ] net.isready() returns true
- [ ] Valid IP address from net.get_ipaddr()
- [ ] GNSS fix obtained (outdoor test)
- [ ] MQTT/HTTP connection to IoT platform works
- [ ] FOTA update procedure tested

## Key References
- FUFU Air780EG AliExpress: https://www.aliexpress.com/i/1005005187346475.html
- FUFU Air780EG Alt: https://pt.aliexpress.com/item/1005009149830358.html
- LuatOS Documentation: https://docs.openluat.com
- Air780EG Wiki: https://wiki.luatos.com/chips/air780e/air780eg.html
## MQTT Configuration (.env)

The tracker uses MQTT for IoT platform communication. Configuration is loaded from `.env` file.

### .env File Format
```env
MQTT_BROKER=mqtt.openluat.com
MQTT_PORT=1883
MQTT_CLIENT_ID=air780eg_tracker_XXXXX
MQTT_USERNAME=YOUR_USERNAME
MQTT_PASSWORD=YOUR_PASSWORD
MQTT_TOPIC=tracker/position
MQTT_KEEPALIVE=60
```

### Lua .env Loader
```lua
-- loadenv.lua - Simple .env loader
-- Place this at the top of main.lua or in a separate module

local M = {}

function M.load(path)
    path = path or ".env"
    local file = io.open(path, "r")
    if not file then
        log.info("ENV", "No .env file found, using defaults")
        return
    end
    
    for line in file:lines() do
        -- Skip comments and empty lines
        if line and not line:match("^%s*#") and line:match("=") then
            local key, value = line:match("^(%S+)=(.*)$")
            if key and value then
                -- Set as global variable _G.KEY
                _G[key] = value
                log.info("ENV", "Loaded:", key, "=", value)
            end
        end
    end
    file:close()
end

return M
```

### Main.lua with .env and MQTT
```lua
-- main.lua - FUFU Air780EG Tracker with MQTT and .env

-- Load environment configuration
loadenv = require("loadenv")
loadenv.load(".env")

-- MQTT configuration from .env (with defaults)
local broker = _G.MQTT_BROKER or "mqtt.openluat.com"
local port = tonumber(_G.MQTT_PORT) or 1883
local client_id = _G.MQTT_CLIENT_ID or "air780eg_tracker"
local username = _G.MQTT_USERNAME or ""
local password = _G.MQTT_PASSWORD or ""
local topic = _G.MQTT_TOPIC or "tracker/position"
local keepalive = tonumber(_G.MQTT_KEEPALIVE) or 60

log.info("MQTT_CONFIG", "Broker:", broker, "Port:", port)
log.info("MQTT_CONFIG", "ClientID:", client_id)
log.info("MQTT_CONFIG", "Topic:", topic)

-- MQTT client
local mqtt = require("mqtt")
local client = mqtt.client(broker, port, client_id, username, password)

-- Connect to MQTT
function connect_mqtt()
    log.info("MQTT", "Connecting to", broker .. ":" .. port)
    client:connect()
    
    -- Subscribe to position topic (if needed)
    client:subscribe(topic, 0, function(data)
        log.info("MQTT", "Subscribed to", topic)
    end)
end

-- Publish position data
function publish_position(lat, lon, altitude, speed)
    if not client:isConnected() then
        connect_mqtt()
    end
    
    local data = {
        latitude = lat,
        longitude = lon,
        altitude = altitude,
        speed = speed,
        timestamp = os.time()
    }
    
    local payload = json.encode(data)
    client:publish(topic, 0, 0, payload)
    log.info("MQTT_PUBLISH", "Published to", topic, "-", payload)
end

-- Main loop
while true do
    -- Get GNSS position
    local lat, lon = gps.latitude(), gps.longitude()
    local alt = gps.altitude()
    local speed = gps.speed()
    
    if lat then
        log.info("POSITION", lat, lon, alt, speed)
        publish_position(lat, lon, alt, speed)
    else
        log.info("GNSS", "Waiting for fix...")
    end
    
    sys.sleep(5000) -- 5 second interval
end
```
- GNSS Design Guide: https://docs.openluat.com/air780eg/luatos/hardware/design/gnssant/