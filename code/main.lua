-- LuatOS Air780EG FUFU Dongle Tracker
-- Main application with MQTT and .env support

PROJECT = "fufu_tracker"
VERSION = "1.0.0"

-- Importar bibliotecas base essenciais
local sys = require("sys")
local json = require("json")

-- Carregar configuração do arquivo .env
local loadenv = require("loadenv")
if loadenv then
    loadenv.load(".env")
end

-- Configurações globais (com Fallbacks)
local broker = _G.MQTT_BROKER or "mqtt.openluat.com"
local port = tonumber(_G.MQTT_PORT) or 1883
local topic = _G.MQTT_TOPIC or "tracker/position"
local username = _G.MQTT_USERNAME or ""
local password = _G.MQTT_PASSWORD or ""
local keepalive = tonumber(_G.MQTT_KEEPALIVE) or 60

uart.setup(1, 115200)
log.setPort(1)
log.info("TRACKER_START", "FUFU Air780EG Tracker Iniciando...")

-- Função para capturar o IMEI/ID único de forma segura no LuatOS
function get_nodeid()
    if mobile then
        return mobile.imei()
    end
    return "fufu_" .. (mobile.iccid() or "unknown")
end

local client_id = _G.MQTT_CLIENT_ID or "fufu_air780eg_" .. get_nodeid()

-- Inicialização e ativação física do GPS (Air530Z interno da Air780EG)
function init_gnss()
    log.info("GNSS", "Ativando chip de GPS interno...")
    -- Liga a alimentação do chip GNSS (Porta serial interna compartilhada no EC618)
    libgnss.clear() 
    -- Configura o modo de saída padrão do circuito integrado de posicionamento da Air780EG
    pm.power(pm.GPS, true)
end

-- Task principal do Tracker (Previne o travamento do sistema)
sys.taskInit(function()
    -- 1. Inicializa o GPS interno
    init_gnss()

    -- 2. Aguarda pacientemente a conexão com a rede celular e obtenção de IP
    log.info("NETWORK", "Aguardando sinal celular e IP da operadora...")
    sys.waitUntil("IP_READY", 30000)
    
    if not socket.isReady() then
        log.error("NETWORK", "Falha ao obter IP da rede celular. Reiniciando...")
        sys.restart()
        return
    end
    log.info("NETWORK", "Conectado na rede celular com sucesso!")

    -- 3. Inicializa o cliente MQTT
    local mqtt = require("mqtt")
    local client = mqtt.client(broker, port, client_id, username, password)
    
    log.info("MQTT", "Conectando ao broker: " .. broker)
    if not client:connect() then
        log.error("MQTT", "Falha de conexão inicial com o Broker")
    end

    -- 4. Loop de Telemetria Cooperativo
    while true do
        -- Mantém ou restabelece o status da conexão MQTT de forma assíncrona
        if not client:isConnected() then
            log.info("MQTT", "Reconectando ao broker...")
            client:connect()
        end

        if client:isConnected() then
            -- Coleta de dados do GPS estruturado do LuatOS via rmc/gga
            local rmc = libgnss.getRmc(2) -- Pega coordenadas prontas convertidas
            
            if rmc and rmc.valid then
                log.info("GNSS_FIX", string.format("Lat: %.6f, Lon: %.6f", rmc.lat, rmc.lng))
                
                -- Estrutura o payload JSON exatamente como seu backend espera
                local payload_data = {
                    id = get_nodeid(),
                    latitude = rmc.lat,
                    longitude = rmc.lng,
                    altitude = libgnss.getGga(3) and libgnss.getGga(3).altitude or 0,
                    speed = rmc.speed or 0,
                    satellites = libgnss.getGsv(3) and libgnss.getGsv(3).total_sats or 0,
                    timestamp = sys.mstime()
                }
                
                local success, payload = pcall(json.encode, payload_data)
                if success then
                    client:publish(topic, 0, 0, payload)
                    log.info("MQTT_PUB", "Dados de localização enviados.")
                end
            else
                log.info("GNSS", "Aguardando sincronização com satélites (Fix)...")
            end
        end

        -- IMPORTANTE: Dorme sem bloquear as rotinas de rede em background do modem
        sys.sleep(10000) 
    end
end)

-- Mantém o loop interno do sistema operacional rodando
sys.run()
