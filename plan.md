# LuatOS Air780EG Tracker - FUFU Dongle Project Plan

## Overview

GPS tracker built on the FUFU Air780EG USB dongle. The device reads its internal
GPS + Beidou receiver, builds a JSON position report and publishes it to an MQTT
broker over LTE. Configuration lives in a `.env` file that is flashed next to the
Lua scripts.

All API names in this document were verified against the LuatOS sources
(`components/`, `luat/modules/`, `script/libs/`) and the official Air780EG demos.
Earlier revisions of this file used APIs that do not exist in LuatOS; those
samples are gone.

## Hardware Platform

### FUFU Air780EG USB Dongle
- Form factor: compact USB "pendrive" dongle
- Connectivity: NDIS/USB plug and play (no drivers on the host)
- Cellular: LTE Cat.1, automatic network registration after SIM + USB power
- GNSS: internal GPS + Beidou receiver (L1), optional active antenna on GNSS_VCC
- Power: bus powered from the USB host (5 V, regulated on board)
- SIM: Nano SIM slot, must be inserted before power up
- Boot: plugging into USB powers the module, no PWR key
- Host sees a network interface (NDIS), not a serial port

### Critical notes for this board
- The network stack is the internal one, driven by the `socket` library and the
  `IP_READY` event. There is no AT command channel to drive.
- The internal GNSS chip is wired to **uart2 at 115200 baud**. It stays silent
  until `pm.power(pm.GPS, true)` is called and `libgnss.bind(2)` attaches the
  stream. Powering the chip alone produces no fix, ever.
- GNSS and GNSS_ANT are switched together by `pm.power(pm.GPS, ...)`.
- The module is EC618, so `rtos.bsp()` returns `"EC618"`.

## Software Requirements
- LuatOS firmware for EC618 / Air780EG (V1103 or newer, V1107 tested by OpenLuat)
- Core libraries: `sys`, `log`, `json`, `socket`, `uart`, `pm`, `libgnss`,
  `mobile`, `mcu`, `mqtt` (MQTT 3.1.1 only), `rtos`
- Script libraries, enabled with "add default lib" in LuaTools: `sysplus`
  (required by the mqtt library on EC618) and `libfota2` (FOTA)
- LuaTools for flashing scripts + `.env`, or `ectool` for `.binpkg`/`.soc`

## File Structure
```
luatos_tracker/
  code/
    main.lua           entry point: boot, network wait, MQTT, tracking loop
    projectConfig.lua  defaults + .env overrides, returns the config table
    loadenv.lua        minimal .env parser (/luadb/.env, then .env)
    gnss.lua           internal GNSS open/read/close wrapper
    fota.lua           remote update through libfota2
    .env.example       configuration template (copy to .env, git-ignored)
  tools/
    sim.lua            offline harness: stubs LuatOS, runs main.lua, asserts
  plan.md
```

## Configuration

Order of precedence: `/luadb/.env` (or `.env`) > built-in defaults in
`projectConfig.lua`. Flashed files are read only and appear under `/luadb`, so a
plain relative `.env` is only used when the scripts are run from the filesystem
root, which is why `loadenv.lua` probes `/luadb/.env` first.

`.env` must be part of the script project uploaded by LuaTools; it lands in
`/luadb/.env`. The file is git-ignored, `code/.env.example` is the template.

```env
MQTT_BROKER=j16c09e0.ala.us-east-1.emqxsl.com
MQTT_PORT=8883
MQTT_SSL=1
MQTT_CLIENT_ID=
MQTT_USERNAME=tracker
MQTT_PASSWORD=secret
MQTT_TOPIC=gps/tracker/fufu_air780eg/location
MQTT_KEEPALIVE=60
MQTT_RECONNECT_MS=5000
MQTT_QOS=1

GNSS_UART=2
GNSS_BAUD=115200
GNSS_DEBUG=0

POSITION_INTERVAL=10000
HEARTBEAT_INTERVAL=60000
NET_TIMEOUT=60000

PRODUCT_KEY=your_64_character_key_from_iot.openluat.com
LOG_LEVEL=INFO
```

Notes:
- `MQTT_SSL` defaults to 1 when `MQTT_PORT` is 8883 or 8884 (EMQX Cloud and most
  managed brokers). TLS here means encrypted without certificate verification.
- `MQTT_CLIENT_ID` must be unique per device. Empty means "use the IMEI"; a
  literal `$imei` inside the value is substituted, for example `tracker_$imei`.
- `MQTT_KEEPALIVE` is clamped to 15..600 seconds by the mqtt library.
- `LOG_LEVEL` accepts SILENT / DEBUG / INFO / WARN / ERROR / FATAL.
- `luatool`-style tools cannot flash a `.env` alone; it goes with the scripts.

## Verified API Compatibility

Wrong calls found in the first version of this project, and what to use instead:

| Not available | Correct API |
| --- | --- |
| `mqtt.client(host, port, id, user, pass)` | `mqtt.create(nil, host, port, ssl)` + `:auth(id, user, pass)` |
| `mqttc:isConnected()` | `mqttc:ready()`, `mqttc:state()` (0 disconnect, 3 ready) |
| `mqttc:publish(topic, 0, 0, payload)` | `mqttc:publish(topic, payload, qos, retain)` |
| `sys.sleep(ms)` | `sys.wait(ms)` inside a task |
| `sys.restart()` | `rtos.reboot()` |
| `sys.info()` | `rtos.version()`, `rtos.bsp()`, `rtos.meminfo()` |
| `sys.mstime()` | `os.time()` (after `socket.sntp()`), or the RMC utc fields |
| `log.setPort(1)` | `log.setLevel(level)`; the log port is a firmware setting |
| `socket.isReady()` | `socket.adapter()` (returns `isReady, index`) |
| `net.isready()`, `net.get_ipaddr()` | `socket.adapter()`, plus the `IP_READY` event |
| `gps.latitude()`, `gps.close()` | `libgnss.getRmc(2)`, `pm.power(pm.GPS, false)` |
| `libgnss.getGga(3).altitude` | `libgnss.getGga(2).altitude` (mode 3 is the raw NMEA string) |
| `libgnss.getGsv(3).total_sats` | `libgnss.getGsv()`; for satellites in the fix use `gga.satellites_tracked` |
| `ota.check()`, `ota.install()` | `libfota2.request(cbFnc, opts)` |

`mqtt` also requires `_G.sysplus = require("sysplus")` on EC618 before use.

## GNSS Setup

The receiver needs power, an uart and a bind, in that order:

```lua
libgnss.clear()
uart.setup(2, 115200)                    -- internal GNSS is on uart2
pm.power(pm.GPS, true)                   -- GNSS + antenna supply
libgnss.bind(2, uart.VUART_0)            -- attach parser, forward a copy (optional)
sys.wait(200)                            -- receiver boot time
sys.subscribe("GNSS_STATE", function(event) log.info("GNSS", event) end) -- FIXED / LOSE
```

Reading a position, with units normalised:

```lua
if libgnss.isFix() then
    local rmc = libgnss.getRmc(2)        -- 2 = decimal degrees
    local gga = libgnss.getGga(2)        -- table, not the raw sentence
    local gsv = libgnss.getGsv()         -- no argument
    -- rmc.speed is in knots: km/h = knots * 1.852
    log.info("POS", rmc.lat, rmc.lng, (rmc.speed or 0) * 1.852,
             gga and gga.altitude, gga and gga.satellites_tracked)
end
```

Antenna guidance: 50 ohm match, short trace, keep the antenna away from the
DCDC and from metal taller than the antenna. GNSS_VCC is a 3.3 V output meant
for an active antenna only; a 5 V active antenna needs its own supply.

First fix is cold start: minutes indoors, tens of seconds outdoors with a clear
sky. AGNSS (ephemeris download plus `lbsLoc2`) shortens it and is optional.

## MQTT with TLS

```lua
_G.sysplus = require("sysplus")                       -- required on EC618
local mqttc = mqtt.create(nil, host, port, ssl)       -- ssl=true for 8883/8884
mqttc:auth(client_id, username, password)
mqttc:keepalive(60)                                   -- clamped to 15..600
mqttc:autoreconn(true, 5000)                          -- library reconnects for us
mqttc:on(function(client, event, data, payload)
    -- conack / suback / sent / recv / disconnect / pong / error
end)
mqttc:connect()
sys.waitUntil("mqtt_conack", 15000)
```

Rules that matter for a tracker:
- The library is MQTT 3.1.1 only, and it has **no uplink retransmission**. Use
  QoS 1 and watch the `sent` event if delivery must be confirmed.
- `connect()` only starts the handshake. Publishing is safe once
  `mqttc:ready()` is true, which follows the `conack` event.
- A duplicated client id makes the broker disconnect the other session, so never
  hardcode one id for a fleet.
- TLS with `ssl=true` encrypts without certificate verification and costs no
  extra configuration. Enable it whenever the broker port is 8883 or 8884.


## Position Report

One JSON object per publish, QoS 1, not retained:

```json
{
  "id": "860000000000001",
  "lat": -23.4068813,
  "lng": -46.6312417,
  "alt": 760.1,
  "spd_kmh": 12.3,
  "course": 73.98,
  "sats_used": 9,
  "sats_visible": 14,
  "hdop": 0.9,
  "fixq": 1,
  "csq": 21,
  "rsrp": -88,
  "ts": 1762731072,
  "utc": "2026-11-09T00:31:12Z",
  "seq": 42,
  "v": "001.000.000"
}
```

Field notes:
- `lat` / `lng`: decimal degrees, negative is south / west
- `alt`: metres above mean sea level, from GGA
- `spd_kmh`: **km/h**, converted from the knots that RMC carries
- `course`: degrees from north, clockwise
- `sats_used`: satellites in the fix (GGA); `sats_visible`: satellites in view (GSV)
- `fixq`: 0 no fix, 1 single point, 2 differential
- `csq`: 0..31 signal quality, `rsrp`: dBm
- `ts`: `os.time()` in seconds since the epoch, wrong until NTP succeeds
- `utc`: receiver supplied UTC timestamp, independent of the module clock
- `seq`: increments per report, restarts at boot
- `v`: script version, the same value reported to the FOTA server

## Tracking Behaviour

- The GNSS receiver starts before the network wait, because the first fix is the
  slowest step.
- Boot waits up to `NET_TIMEOUT` for an IP (`socket.adapter()`), then reboots.
- `socket.sntp()` plus `NTP_UPDATE` gives a wall clock for `ts`. Failure is not
  fatal: `utc` still carries the receiver time.
- Every `POSITION_INTERVAL` the device samples GNSS. A report is published when
  the position or speed changed, or when `HEARTBEAT_INTERVAL` elapsed since the
  last report, so a parked tracker does not burn SIM data.
- MQTT reconnection is delegated to `autoreconn`; the loop only re-issues
  `connect()` when the state is disconnected.
- `errDump.config(true, 600)` keeps script errors on flash and uploads them.

## FOTA

```lua
local libfota2 = require("libfota2")
libfota2.request(function(result)
    if result == 0 then rtos.reboot() end          -- 0 = package downloaded
end, { project_key = PRODUCT_KEY, timeout = 120000 })
```

Requirements:
- `PRODUCT_KEY` set in `.env` (from iot.openluat.com)
- `VERSION` in `main.lua` written as `XXX.YYY.ZZZ`, three digits per group,
  for example `001.000.000`. The library parses it with `(%d+)%.(%d+)%.(%d+)`
  and result code 5 means it could not.
- Result codes: 0 success, 1 connection failed, 2 bad url, 3 server closed,
  4 bad body or no update, 5 bad version or missing project key.
- `fota.lua` exposes `check()`, `auto_check(interval_ms)` and `version()`, and
  does nothing when `libfota2` is missing from the build.


## Development Workflow

1. Insert the Nano SIM.
2. Connect the antenna, then plug the dongle into USB.
3. Wait 5 to 10 s for the NDIS interface and the cellular registration.
4. Copy `code/.env.example` to `code/.env` and fill in the broker details.
5. LuaTools: select the EC618 LuatOS firmware, add the `code/` files, enable
   "add default lib" (needed for `sysplus` and `libfota2`), then download.
6. Watch the log: `BOOT`, `CONFIG`, `GNSS power on`, `NET IP ready`,
   `MQTT connected`, `MQTT published`.
7. Test outdoors for a fix. Indoors only LBS assisted AGNSS could help.

Deployment constraints:
- `ectool` (the Python tool in this repo) burns `.binpkg` or `.soc` only;
  flashing `script.bin` alone is still unimplemented there. Use LuaTools for the
  script project, or build a binpkg that already contains the scripts.
- The `.env` file must be part of that script project to reach `/luadb/.env`.
- `pm.power(pm.PWK_MODE, false)` is set at boot so flashing does not need the
  boot key dance.

## Offline Validation

`tools/sim.lua` stubs `sys`, `log`, `json`, `uart`, `pm`, `mobile`, `mcu`,
`libgnss`, `socket`, `rtos`, `errDump`, `mqtt`, `sysplus` and `libfota2`, feeds a
canned RMC/GGA/GSV sample, runs `main.lua` for 300 scheduler steps and asserts
the result:

```bash
lua tools/sim.lua        # exit code 0 = all checks passed
```

It verifies the `.env` parser, keepalive clamping, TLS selection from the port,
client id fallback to the IMEI, GNSS uart/bind/power, QoS and retain of the
publish, and the exact JSON payload (including `spd_kmh` from knots).
The harness points `LUATOS_ENV_FILE` at a temporary file, so the real `.env` of
the repository is never parsed and no credential reaches the log.

## Testing Checklist
- [ ] Nano SIM inserted, antenna connected
- [ ] `CONFIG` lines show the expected broker, port, TLS and topic
- [ ] `socket.adapter()` returns true and `NET IP ready` appears
- [ ] `MQTT connected as <id>` after `conack`
- [ ] `GNSS FIXED` outdoors, `libgnss.isFix()` true
- [ ] Payload visible on the broker with `spd_kmh` in km/h
- [ ] Stationary device stops publishing, sends one heartbeat per interval
- [ ] Broker restart triggers an automatic reconnect, no reboot needed
- [ ] `lua tools/sim.lua` exits 0
- [ ] FOTA: `PRODUCT_KEY` set, `VERSION` in XXX.YYY.ZZZ form

## Troubleshooting
- No fix after minutes: confirm the antenna, then check that
  `uart.setup(2, 115200)` and `libgnss.bind(2)` both ran, and set
  `GNSS_DEBUG=1` to see the sentences.
- `MQTT error conack`: wrong credentials, or a duplicate client id kicking the
  session. Use an IMEI based client id.
- Connection times out on port 8883: TLS is off, check `MQTT_SSL`.
- Publishes report success but the server shows nothing: confirm topic and QoS,
  then check for `sent` events.
- `publish` returns nil: the socket is gone, the client is not ready.
- Reboot loop at boot: no SIM data or no coverage, `NET_TIMEOUT` expired.

## Key References
- LuatOS docs: https://docs.openluat.com
- Air780EG MQTT demo: https://docs.openluat.com/air780eg/luatos/app/socket/mqtt/
- MQTT API: https://docs.openluat.com/osapi/core/mqtt/
- libgnss API: https://docs.openluat.com/osapi/core/libgnss/
- libfota2 API: https://docs.openluat.com/osapi/ext/libfota2/
- io / file paths: https://docs.openluat.com/osapi/core/io/
- GNSS antenna design guide:
  https://docs.openluat.com/air780eg/luatos/hardware/design/gnssant/
- LuatOS source (authoritative API): https://github.com/openLuat/LuatOS

