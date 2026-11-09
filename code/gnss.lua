-- gnss.lua - internal GNSS (GPS + Beidou) of the Air780EG, parsed by libgnss
-- Without libgnss.bind() the library never sees NMEA data and isFix() stays
-- false forever, which is the classic "GPS powered but no fix" trap.

local M = {
    uart_id = 2,
    baud = 115200,
    opened = false,
    fix = false,
}

local KNOT_TO_KMH = 1.852  -- RMC speed is delivered in knots, we report km/h

local function round2(value)
    return math.floor(value * 100 + 0.5) / 100
end

-- Power the chip, configure its uart and hand the stream to libgnss.
-- debug=true dumps every NMEA sentence; useful while bringing up an antenna.
function M.open(uart_id, baud, debug)
    uart_id = uart_id or M.uart_id
    baud = baud or M.baud
    M.uart_id = uart_id
    M.baud = baud

    log.info("GNSS", "power on, uart", uart_id, baud)
    libgnss.clear()
    uart.setup(uart_id, baud)
    pm.power(pm.GPS, true)          -- Air780EG: GNSS and GNSS_ANT switch together

    -- bind() is what makes libgnss consume the sentences; the second argument
    -- forwards a copy to a virtual uart for sniffing (firmware >= 2023-01-02)
    if uart.VUART_0 then
        libgnss.bind(uart_id, uart.VUART_0)
    else
        libgnss.bind(uart_id)
    end

    sys.wait(200)                   -- receiver boot time before sentences flow
    if debug and libgnss.debug then
        libgnss.debug(true)
    end
    M.opened = true

    sys.subscribe("GNSS_STATE", function(event)
        M.fix = (event == "FIXED")
        log.info("GNSS", event)
    end)
end

function M.is_fix()
    return M.fix or libgnss.isFix()
end

-- Snapshot of the last position, or nil while there is no valid fix.
-- Units are normalised here so the payload never lies about them.
function M.read()
    if not M.is_fix() then
        return nil
    end

    local rmc = libgnss.getRmc(2)   -- mode 2 = decimal degrees, not DDMM.MMMM
    if not rmc or not rmc.valid then
        return nil
    end

    local gga = libgnss.getGga(2)   -- mode 3 would return the raw NMEA string
    local gsv = libgnss.getGsv()    -- takes no argument; counts visible satellites

    local utc
    if rmc.year and rmc.month and rmc.day then
        utc = string.format("%04d-%02d-%02dT%02d:%02d:%02dZ",
            rmc.year, rmc.month, rmc.day, rmc.hour or 0, rmc.min or 0, rmc.sec or 0)
    end

    return {
        lat = rmc.lat,
        lng = rmc.lng,
        alt = gga and gga.altitude or nil,                 -- metres above sea level
        spd_kmh = round2((rmc.speed or 0) * KNOT_TO_KMH),  -- knots -> km/h
        course = rmc.course or 0,                          -- degrees, 0 = north
        sats_used = gga and gga.satellites_tracked or nil, -- satellites in the fix
        sats_visible = gsv and gsv.total_sats or nil,      -- satellites in view
        hdop = gga and gga.hdop or nil,
        fixq = gga and gga.fix_quality or nil,             -- 0 no fix, 1 GPS, 2 DGPS
        utc = utc,
    }
end

-- Standby: receiver off, uart released (~500uA instead of tens of mA)
function M.close()
    pm.power(pm.GPS, false)
    uart.close(M.uart_id)
    M.opened = false
    M.fix = false
    log.info("GNSS", "powered off")
end

return M
