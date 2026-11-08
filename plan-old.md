# LuatOS Air780EG Tracker System - FUFU Dongle Project Plan

## Overview
Tracker using FUFU Air780EG USB dongle (NDIS/USB mode) for outdoor IoT positioning.
## Hardware Platform
### FUFU Air780EG USB Dongle
- Form factor: Compact "pendrive" style USB dongle
- Connectivity: NDIS/USB plug-and-play mode (no drivers needed)
## Critical Notes (FUFU Dongle Specific)

### USB NDIS Mode (Critical)
- Network works via NDIS/USB, NOT UART AT commands
## Software Requirements
- LuatOS firmware V1103+ for full Air780EG support
- GNSS library: gns API
- Network: net library (NDIS/USB mode, not UART AT)
## File Structure
```luatos_tracker/code/main.lua
luatos_tracker/code/projectConfig.lua
luatos_tracker/code/fota.lua
## Minimal main.lua (FUFU Version)
```lua
log.info("FUFU_TEST", "Starting FUFU Air780EG test")
sys.wait(5000) -- Wait for NDIS initialization
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
## Development Workflow
1. Insert Nano SIM card
2. Plug FUFU dongle into USB host
3. Wait 5-10s for NDIS initialization
## Testing Checklist
- [ ] Nano SIM card inserted
- [ ] Plugged into USB host
- [ ] Wait 5-10s for NDIS init
## Key References
- FUFU Air780EG AliExpress: https://www.aliexpress.com/i/1005005187346475.html
- FUFU Air780EG Alt: https://pt.aliexpress.com/item/1005009149830358.html
- LuatOS Documentation: https://docs.openluat.com
- Air780EG Wiki: https://wiki.luatos.com/chips/air780e/air780eg.html
- GNSS Design Guide: https://docs.openluat.com/air780eg/luatos/hardware/design/gnssant/
- [ ] net.isready() returns true
- [ ] Valid IP address from net.get_ipaddr()
- [ ] GNSS fix obtained (outdoor test)
- [ ] MQTT/HTTP connection to IoT platform works
- [ ] FOTA update procedure tested
4. Test network: net.isready(), net.get_ipaddr()
5. Test GNSS: gps.latitude/longitude() (outdoor recommended)
6. Run tracking loop, send position to IoT platform
7. FOTA: Configure PRODUCT_KEY in projectConfig.lua, use LuaTools for updates
- GNSS_VCC provides 3.3V for active antenna (verify on model)

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
```
- MQTT/HTTP: For IoT platform data transmission
- LuaTools: For firmware flashing via USB
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
- Cellular: 4G Cat.1 LTE (automatic network registration after SIM + USB)
- GNSS: Integrated or external antenna (varies by specific model)
- Power: Bus-powered from USB host (5V, regulated on board)
- SIM: Nano SIM card slot required
- Boot: Plug into USB host (no external PWR key needed)
- OS recognition: Appears as network interface (NDIS), not serial port