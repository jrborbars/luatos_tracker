-- LuatOS Air780EG tracker: internal GNSS -> MQTT position reports
-- PROJECT and VERSION are read by LuaTools; VERSION must be XXX.YYY.ZZZ
-- (three digits per group) to work with FOTA on iot.openluat.com.

PROJECT = "fufu_tracker"
VERSION = "001.000.000"

local sys = require("sys")
local json = require("json")

-- EC618 (Air780EG): the power-key debounce makes flashing awkward, turn it off
if rtos and rtos.bsp and pm and pm.PWK_MODE and rtos.bsp() == "EC618" then
    pm.power(pm.PWK_MODE, false)
end

-- Keep script errors on flash and upload them; a remote tracker is hard to debug
if errDump then
    errDump.config(true, 600)
end

local cfg = require("projectConfig")
local gnss = require("gnss")

log.setLevel(cfg.LOG_LEVEL)
log.info("BOOT", PROJECT, cfg.VERSION, "bsp", tostring(rtos.bsp()))

-- Device identity, resolved once: IMEI -> ICCID -> MCU id -> fixed fallback.
-- mobile.* needs pcall: it returns nil (or errors) while the SIM is busy.
local node_id
function get_nodeid()
    if node_id then
        return node_id
    end
    local probes = {
        function() return mobile.imei() end,
        function() return mobile.iccid() end,
        function() return mcu.unique_id() end,
    }
    for _, probe in ipairs(probes) do
        local ok, value = pcall(probe)
        if ok and type(value) == "string" and value:match("^[%w_%.%-]+$") then
            node_id = value
            break
        end
    end
    node_id = node_id or "fufu_unknown"
    log.info("ID", "node id", node_id)
    return node_id
end

-- socket.adapter() returns (isReady, index); socket.isReady() no longer exists
local function net_ready()
    if socket and socket.adapter then
        return socket.adapter() and true or false
    end
    return false
end

local function diag()
    local csq, rsrp
    local ok, value = pcall(mobile.csq)
    if ok then
        csq = value
    end
    ok, value = pcall(mobile.rsrp)
    if ok then
        rsrp = value
    end
    return csq, rsrp
end

-- MQTT -------------------------------------------------------------------
local mqtt_client
local mqtt_ready = false
local mqtt_acked = 0

-- mqtt is a built-in library; sysplus is required by it on EC618
local function load_mqtt()
    local ok, sysplus = pcall(require, "sysplus")
    if ok and sysplus then
        _G.sysplus = sysplus
    end
    if type(mqtt) ~= "table" then
        local ok2, lib = pcall(require, "mqtt")
        if ok2 and lib then
            mqtt = lib
        end
    end
    return type(mqtt) == "table" and mqtt.create ~= nil
end

local function mqtt_create()
    if not load_mqtt() then
        log.error("MQTT", "mqtt library missing in this firmware")
        return false
    end

    local client_id = cfg.MQTT_CLIENT_ID
    if client_id == "" then
        client_id = get_nodeid()
    elseif client_id:find("%$imei") then
        -- allow MQTT_CLIENT_ID=<prefix>$imei in .env
        client_id = client_id:gsub("%$imei", get_nodeid())
    end

    local client = mqtt.create(nil, cfg.MQTT_BROKER, cfg.MQTT_PORT, cfg.MQTT_SSL)
    if not client then
        log.error("MQTT", "create failed")
        return false
    end

    client:auth(client_id, cfg.MQTT_USERNAME, cfg.MQTT_PASSWORD)
    client:keepalive(cfg.MQTT_KEEPALIVE)
    client:autoreconn(true, cfg.MQTT_RECONNECT_MS)

    client:on(function(_, event, data, payload)
        if event == "conack" then
            mqtt_ready = true
            log.info("MQTT", "connected as", client_id)
            sys.publish("mqtt_conack")
        elseif event == "sent" then
            mqtt_acked = mqtt_acked + 1
            log.debug("MQTT", "acked", data, "total", mqtt_acked)
        elseif event == "disconnect" then
            mqtt_ready = false
            log.warn("MQTT", "disconnected, autoreconn handles it")
        elseif event == "error" then
            mqtt_ready = false
            log.error("MQTT", "error", data, payload)
        elseif event == "recv" then
            log.info("MQTT", "downlink", data, payload)
        end
    end)

    mqtt_client = client
    if not client:connect() then
        log.error("MQTT", "connect refused")
        return false
    end
    sys.waitUntil("mqtt_conack", 15000)
    return client:ready()
end

local function mqtt_ensure()
    if not mqtt_client then
        return mqtt_create()
    end
    if mqtt_client:ready() then
        return true
    end
    -- state 0 == MQTT_STATE_DISCONNECT; autoreconn retries the rest on its own
    if mqtt_client:state() == 0 then
        log.info("MQTT", "reconnecting to", cfg.MQTT_BROKER)
        mqtt_client:connect()
    end
    return false
end

-- Telemetry --------------------------------------------------------------
local seq = 0
local last_pos
local last_report_ts = 0

local function moved(current, previous)
    if not previous then
        return true
    end
    if current.lat ~= previous.lat or current.lng ~= previous.lng then
        return true
    end
    if math.abs((current.spd_kmh or 0) - (previous.spd_kmh or 0)) >= 1 then
        return true
    end
    return false
end

local function publish_position(pos)
    local csq, rsrp = diag()
    seq = seq + 1

    local data = {
        id = get_nodeid(),
        lat = pos.lat,
        lng = pos.lng,
        alt = pos.alt,          -- metres
        spd_kmh = pos.spd_kmh,  -- km/h, not knots
        course = pos.course,    -- degrees from north
        sats_used = pos.sats_used,
        sats_visible = pos.sats_visible,
        hdop = pos.hdop,
        fixq = pos.fixq,
        csq = csq,
        rsrp = rsrp,
        ts = os.time(),
        utc = pos.utc,
        seq = seq,
        v = cfg.VERSION,
    }

    local ok, payload = pcall(json.encode, data)
    if not ok or not payload then
        log.error("MQTT", "json encode failed", payload)
        return false
    end

    -- mqttc:publish(topic, data, qos, retain) -- argument order matters
    local message_id = mqtt_client:publish(cfg.MQTT_TOPIC, payload, cfg.MQTT_QOS, 0)
    if not message_id then
        log.error("MQTT", "publish rejected", payload)
        return false
    end

    log.info("MQTT", "published seq", seq, "msgid", message_id)
    log.debug("MQTT", payload)
    return true
end

-- Main task --------------------------------------------------------------
sys.taskInit(function()
    -- Start the receiver first: the first fix takes tens of seconds outdoors
    gnss.open(cfg.GNSS_UART, cfg.GNSS_BAUD, cfg.GNSS_DEBUG)

    log.info("NET", "waiting for cellular IP")
    local waited = 0
    while waited < cfg.NET_TIMEOUT do
        if net_ready() then
            break
        end
        sys.wait(1000)
        waited = waited + 1000
    end
    if not net_ready() then
        log.error("NET", "no IP after", cfg.NET_TIMEOUT, "ms, rebooting")
        sys.wait(5000)
        rtos.reboot()
        return
    end
    log.info("NET", "IP ready")

    -- Wall clock for timestamps; the RMC utc field is reported as well
    if socket and socket.sntp then
        socket.sntp()
        sys.waitUntil("NTP_UPDATE", 5000)
    end
    log.info("TIME", "os.time", os.time())

    local heartbeat_s = math.floor(cfg.HEARTBEAT_INTERVAL / 1000)

    while true do
        mqtt_ensure()

        local pos = gnss.read()
        if not pos then
            log.info("GNSS", "waiting for fix")
        elseif mqtt_client and mqtt_client:ready() then
            local now = os.time()
            local age = now - last_report_ts
            if moved(pos, last_pos) or age >= heartbeat_s then
                if publish_position(pos) then
                    last_pos = pos
                    last_report_ts = now
                end
            else
                log.debug("TRACK", "stationary, next heartbeat in", heartbeat_s - age, "s")
            end
        else
            log.debug("TRACK", "mqtt offline, position skipped")
        end

        sys.wait(cfg.POSITION_INTERVAL)
    end
end)

sys.run()

