-- tools/sim.lua - offline harness for code/
-- Stubs the LuatOS API surface and runs main.lua for a bounded number of
-- scheduler steps, so logic errors (nil calls, wrong units, bad JSON) show up
-- without hardware. Usage, from the repo root:
--     lua tools/sim.lua

local ROOT = arg and arg[0] and arg[0]:match("^(.*)/tools/") or "."
package.path = ROOT .. "/code/?.lua;" .. package.path

io.stdout:setvbuf("no") -- os.exit() does not flush buffered stdout

local sim = { errors = 0, warns = 0, publishes = {}, reboots = 0 }
local subscribers = {}
local pending = {}
local tasks = {}

local function unpack_args(args)
    if not args then
        return
    end
    return table.unpack(args, 1, args.n or #args)
end

local function deliver(topic, ...)
    local queue = pending[topic]
    if not queue then
        queue = {}
        pending[topic] = queue
    end
    queue[#queue + 1] = { n = select("#", ...), ... }
end

-- sys -------------------------------------------------------------------
local sys = {}
function sys.taskInit(fn, ...)
    tasks[#tasks + 1] = {
        co = coroutine.create(fn),
        args = { n = select("#", ...), ... },
        first = true,
    }
end
function sys.wait(ms) coroutine.yield("wait", ms or 1000) end
function sys.waitUntil(topic)
    local queue = pending[topic]
    if queue and #queue > 0 then
        local event = table.remove(queue, 1)
        return true, unpack_args(event)
    end
    return false
end
function sys.publish(topic, ...)
    deliver(topic, ...)
    local subs = subscribers[topic]
    if subs then
        for _, fn in ipairs(subs) do
            pcall(fn, ...)
        end
    end
    return true
end
function sys.subscribe(topic, fn)
    subscribers[topic] = subscribers[topic] or {}
    subscribers[topic][#subscribers[topic] + 1] = fn
end
function sys.unsubscribe() end
function sys.timerStart() return 0 end
function sys.timerLoopStart() return 0 end
function sys.run()
    local budget = 300
    while budget > 0 and #tasks > 0 do
        budget = budget - 1
        for _, task in ipairs(tasks) do
            if not task.dead then
                local ok, kind, a, b
                if task.first then
                    task.first = false
                    ok, kind, a, b = coroutine.resume(task.co, unpack_args(task.args))
                else
                    ok, kind, a, b = coroutine.resume(task.co, task.resume)
                end
                if not ok then
                    task.dead = true
                    sim.errors = sim.errors + 1
                    print("[sim] task crashed: " .. tostring(kind))
                elseif coroutine.status(task.co) == "dead" then
                    task.dead = true
                else
                    task.resume = (kind == "waitUntil") and sys.waitUntil(a, b) or true
                end
            end
        end
    end
    print("[sim] scheduler stopped after", 300 - budget, "steps")
end

-- log -------------------------------------------------------------------
local log = {}
local function logf(level, ...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    print(string.format("[%s] %s", level, table.concat(parts, " ")))
end
log.info = function(...) logf("info", ...) end
log.warn = function(...) sim.warns = sim.warns + 1; logf("warn", ...) end
log.error = function(...) sim.errors = sim.errors + 1; logf("error", ...) end
log.debug = function(...) logf("debug", ...) end
log.setLevel = function(level) print("[sim] log level " .. tostring(level)) end

-- json ------------------------------------------------------------------
local json = {}
local esc = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function encode(value, out)
    local t = type(value)
    if value == nil then
        out[#out + 1] = "null"
    elseif t == "boolean" then
        out[#out + 1] = tostring(value)
    elseif t == "number" then
        out[#out + 1] = string.format("%.14g", value)
    elseif t == "string" then
        out[#out + 1] = '"' .. value:gsub('[%c"\\]', function(c)
            return esc[c] or string.format("\\u%04x", c:byte())
        end) .. '"'
    elseif t == "table" then
        local keys = {}
        for k in pairs(value) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        out[#out + 1] = "{"
        for i, k in ipairs(keys) do
            if i > 1 then
                out[#out + 1] = ","
            end
            out[#out + 1] = '"' .. tostring(k) .. '":'
            encode(value[k], out)
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "null"
    end
end
function json.encode(value)
    local out = {}
    encode(value, out)
    return table.concat(out)
end
function json.decode() return nil end

-- hardware stubs ---------------------------------------------------------
local uart = { VUART_0 = 200, setups = {} }
function uart.setup(id, baud) uart.setups[#uart.setups + 1] = { id = id, baud = baud } end
function uart.write() return 0 end
function uart.close() end

local pm = { GPS = 1, PWK_MODE = 2, USB = 3, log = {} }
function pm.power(id, on)
    pm.log[#pm.log + 1] = { id = id, on = on }
    return true
end

local mobile = {}
function mobile.imei() return "860000000000001" end
function mobile.iccid() return "89440000000000000001" end
function mobile.csq() return 21 end
function mobile.rsrp() return -88 end

local mcu = {}
function mcu.unique_id() return "A1B2C3D4" end

-- canned values from $GNRMC 3557.35652N / 13854.27058E, 1.681 knots
local gnss_reads = 0
local libgnss = { bound = nil, fix = false }
function libgnss.clear() end
function libgnss.debug() end
function libgnss.bind(id, forward)
    libgnss.bound = id
    libgnss.forward = forward
    libgnss.fix = true
    sys.publish("GNSS_STATE", "FIXED")
end
function libgnss.isFix() return libgnss.fix end
function libgnss.getRmc()
    gnss_reads = gnss_reads + 1
    local drift = math.floor(gnss_reads / 50) * 0.0001 -- forces a new report now and then
    return {
        valid = true,
        lat = 35.9559420 + drift,
        lng = 138.9045097,
        speed = 1.681,
        course = 73.98,
        year = 2023, month = 12, day = 11, hour = 0, min = 6, sec = 25,
    }
end
function libgnss.getGga()
    return { fix_quality = 1, satellites_tracked = 9, hdop = 0.9, altitude = 12.5 }
end
function libgnss.getGsv()
    return { total_sats = 14, sats = {} }
end

local socket = { LWIP_GP = 5 }
function socket.adapter() return true, socket.LWIP_GP end
function socket.sntp()
    sys.publish("NTP_UPDATE")
    return true
end

local rtos = {}
function rtos.bsp() return "EC618" end
function rtos.version() return "LuatOS-SoC_V1107_EC618" end
function rtos.reboot()
    sim.reboots = sim.reboots + 1
    print("[sim] rtos.reboot() requested")
end
function rtos.meminfo() return {} end

local errDump = {}
function errDump.config() return true end


-- mqtt ------------------------------------------------------------------
local mqtt = {}
function mqtt.create(adapter, host, port, ssl)
    local client = {
        host = host, port = port, ssl = ssl,
        ready_flag = false, state_num = 0, published = {},
    }
    function client:auth(id, user, password)
        self.id, self.user, self.password = id, user, password
        return true
    end
    function client:keepalive(seconds) self.keepalive_s = seconds end
    function client:autoreconn(enabled, delay) self.arc, self.arc_ms = enabled, delay end
    function client:on(cb) self.cb = cb end
    function client:connect()
        self.state_num = 3
        self.ready_flag = true
        if self.cb then self.cb(self, "conack", 0, 0) end
        sys.publish("mqtt_conack")
        return true
    end
    function client:ready() return self.ready_flag end
    function client:state() return self.state_num end
    function client:subscribe() return 1 end
    function client:close() self.ready_flag = false; self.state_num = 0 end
    function client:publish(topic, payload, qos, retain)
        if not self.ready_flag then return nil end
        self.published[#self.published + 1] = { topic = topic, payload = payload, qos = qos, retain = retain }
        sim.publishes[#sim.publishes + 1] = self.published[#self.published]
        if self.cb then self.cb(self, "sent", #self.published, 0) end
        return #self.published
    end
    sim.client = client
    return client
end

local libfota2 = {}
function libfota2.request(cb, opts) sim.fota = { cb = cb, opts = opts } end

_G.sys, _G.log, _G.json = sys, log, json
_G.uart, _G.pm, _G.mobile, _G.mcu = uart, pm, mobile, mcu
_G.libgnss, _G.socket, _G.rtos, _G.errDump = libgnss, socket, rtos, errDump
_G.mqtt = mqtt
package.preload["sys"] = function() return sys end
package.preload["json"] = function() return json end
package.preload["mqtt"] = function() return mqtt end
package.preload["sysplus"] = function() return { taskInit = sys.taskInit } end
package.preload["libfota2"] = function() return libfota2 end


-- tests ------------------------------------------------------------------
local failures = 0
local function check(name, ok, detail)
    if ok then
        print(string.format("[PASS] %s", name))
    else
        failures = failures + 1
        print(string.format("[FAIL] %s %s", name, detail or ""))
    end
end

-- 1. .env parser
local env_path = os.tmpname()
local env_fd = assert(io.open(env_path, "w"))
env_fd:write("# comment\n")
env_fd:write("SIMTEST_ALPHA=hello\n")
env_fd:write("export SIMTEST_BETA = \"quoted value\"\n")
env_fd:write("\n")
env_fd:write("SIMTEST_NUMBER=42\n")
env_fd:close()
local loadenv = require("loadenv")
local count = loadenv.parse_file(env_path)
os.remove(env_path)
check("env: key count", count == 3, tostring(count))
check("env: plain value", _G.SIMTEST_ALPHA == "hello", tostring(_G.SIMTEST_ALPHA))
check("env: quoted + export", _G.SIMTEST_BETA == "quoted value", tostring(_G.SIMTEST_BETA))
check("env: number kept as string", _G.SIMTEST_NUMBER == "42", tostring(_G.SIMTEST_NUMBER))

-- 2. configuration for the run, through a temporary .env (not the repo one)
local cfg_env = os.tmpname()
local cfg_fd = assert(io.open(cfg_env, "w"))
cfg_fd:write("MQTT_BROKER=sim.broker\n")
cfg_fd:write("MQTT_PORT=8883\n")          -- TLS port, ssl must switch on
cfg_fd:write("MQTT_CLIENT_ID=\n")         -- empty -> IMEI
cfg_fd:write("MQTT_TOPIC=tracker/position\n")
cfg_fd:write("MQTT_KEEPALIVE=9\n")        -- below the 15 s floor on purpose
cfg_fd:write("POSITION_INTERVAL=10\n")
cfg_fd:write("HEARTBEAT_INTERVAL=1000\n")
cfg_fd:write("NET_TIMEOUT=5000\n")
cfg_fd:write("LOG_LEVEL=INFO\n")
cfg_fd:close()
_G.LUATOS_ENV_FILE = cfg_env

-- 3. run the application
dofile(ROOT .. "/code/main.lua")
os.remove(cfg_env)

-- 4. assertions
local client = sim.client
check("run: no script errors", sim.errors == 0, "errors=" .. sim.errors)
check("run: no reboot", sim.reboots == 0)
check("config: keepalive clamped to 15", client and client.keepalive_s == 15, tostring(client and client.keepalive_s))
check("config: client id from IMEI", client and client.id == "860000000000001", tostring(client and client.id))
check("config: tls on for port 8883", client and client.ssl == true, tostring(client and client.ssl))
check("config: broker and port", client and client.host == "sim.broker" and client.port == 8883)
check("mqtt: autoreconn enabled", client and client.arc == true)
check("gnss: bound to uart2", libgnss.bound == 2, tostring(libgnss.bound))
check("gnss: uart baud 115200", uart.setups[1] and uart.setups[1].baud == 115200)
local gnss_powered = false
for _, entry in ipairs(pm.log) do
    if entry.id == pm.GPS and entry.on == true then
        gnss_powered = true
    end
end
check("gnss: receiver powered", gnss_powered)
check("publish: at least 2 reports", #sim.publishes >= 2, "count=" .. #sim.publishes)

local first = sim.publishes[1]
check("publish: topic", first and first.topic == "tracker/position", first and first.topic)
check("publish: qos 1", first and first.qos == 1, tostring(first and first.qos))
check("publish: retain 0", first and first.retain == 0, tostring(first and first.retain))

local payload = first and first.payload or ""
print("[sim] payload: " .. payload)
for _, needle in ipairs({
    '"id":"860000000000001"',
    '"lat":35.955942',
    '"lng":138.9045097',
    '"spd_kmh":3.11', -- 1.681 knots -> 3.11 km/h
    '"alt":12.5',
    '"sats_used":9',
    '"sats_visible":14',
    '"csq":21',
    '"rsrp":-88',
    '"utc":"2023-12-11T00:06:25Z"',
    '"v":"001.000.000"',
}) do
    check("payload contains " .. needle, payload:find(needle, 1, true) ~= nil)
end

print(string.format("[sim] done: %d publish(es), %d failure(s)", #sim.publishes, failures))
os.exit(failures == 0 and 0 or 1)

