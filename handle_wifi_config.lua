#!/usr/bin/lua

local socket = require("socket")
local cjson = require("cjson")
local io = require("io")

local function handle_request(data, content_type)
    print("Received Data: " .. data)

    -- 确保 Content-Type 为 application/json
    if content_type ~= "application/json" then
        return '{"status":"error","message":"Invalid Content-Type"}', 400
    end

    -- 解析 JSON 数据
    local success, json_data = pcall(cjson.decode, data)
    if not success then
        print("JSON Decode Error: " .. json_data)
        return '{"status":"error","message":"Invalid JSON"}', 400
    end

    local ssid = json_data.ssid
    local passwd = json_data.password

    print("Parsed JSON: ssid=" .. ssid .. ", passwd=" .. passwd)  -- 输出解析后的数据

    if not ssid or not passwd then
        -- 如果缺少 ssid 或 passwd，返回 400 错误
        return '{"status":"error","message":"Invalid SSID or password"}', 400
    end

    -- 调用 wpa_passphrase 生成配置文件
    local config_file = "/tmp/wpa_supplicant.conf"
    local cmd = string.format('wpa_passphrase "%s" "%s"', ssid, passwd)
    local handle = io.popen(cmd .. " 2>&1")  -- 捕获标准输出和错误输出

    -- 获取 wpa_passphrase 输出 及 结果
    local result = handle:read("*a")
    local success = handle:close()

    print("\nwpa_passphrase output:\n" .. (result or ""))

    if not success then
        print("wpa_passphrase failed!")
        return string.format('{"status":"error","message":"%s"}', result), 400
    end
    print("wpa_passphrase success")

    -- 检查文件是否成功创建并且包含内容
    local file = io.open(config_file, "w")
    if not file then
        print("Failed to open wpa_supplicant.conf for writing")  -- 打印错误
        return '{"status":"error","message":"Failed to generate configuration"}', 500
    end

    -- 写入固定的头部内容
    file:write("ctrl_interface=/run/wpa_supplicant\n")
    file:write("ctrl_interface_group=root\n")
    file:write("update_config=1\n\n")

    -- 写入 wpa_passphrase 生成的内容
    file:write(result)

    file:close()

    -- 检查文件内容是否成功写入
    local file_check = io.open(config_file, "r")
    local file_content = file_check:read("*a")
    file_check:close()

    if file_content == "" then
        print("wpa_supplicant.conf is empty")
        return '{"status":"error","message":"Failed to generate configuration"}', 500
    else
        local result = os.execute(string.format("cp %s /opt/gnc/etc/", config_file))
        if not result then
            print("Failed to copy wpa_supplicant.conf")
        end

        print("wpa_supplicant.conf generated successfully")
        return '{"status":"success","message":"Configuration generated successfully"}', 200
    end
end


local function listen_on_socket(host, port)
    local server, err = socket.bind(host, port)
    if not server then
        print("Error binding to port " .. port .. ": " .. err)
        return
    end

    print("Server listening on " .. host .. ":" .. port)

    --server:settimeout(10)  -- 设置服务器超时

    while true do
        local client, err = server:accept()
        if not client then
            print("Error accepting client connection: " .. err)
            break
        end

        client:settimeout(10)           -- 设置客户端超时

        print("Client connected")

        -- 读取请求的头部（直到空行）
        local request_header = {}
        local line, err = client:receive('*l')
        while line and line ~= "" do
            table.insert(request_header, line)
            line, err = client:receive('*l')
        end

        -- 输出请求头，方便调试
        print("Request Headers: ")
        for _, v in ipairs(request_header) do
            print(v)
        end

        -- 获取 Content-Type 和 Content-Length
        local content_type = "application/json"  -- 默认处理 JSON 数据
        local content_length = 0
        for _, header_line in ipairs(request_header) do
            if header_line:match("Content%-Type:") then
                content_type = header_line:match("Content%-Type: ([^%s]+)")  -- 获取 Content-Type
            elseif header_line:match("Content%-Length:") then
                content_length = tonumber(header_line:match("Content%-Length: (%d+)"))  -- 获取 Content-Length
            end
        end

        -- 读取请求体（根据 Content-Length）
        local data, err = client:receive(content_length)
        if not err then
            local response, status_code = handle_request(data, content_type)

            -- 生成 HTTP 响应头
            local content_length = string.len(response)
            local response_header = string.format(
                "HTTP/1.1 %d OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n",
                status_code, content_length
            )

            -- 发送响应
            client:send(response_header)
            client:send(response)

            if status_code == 200 then
                print("Exit condition met. Terminating script.")
                client:close()
                os.exit(0) -- 0 表示正常退出
            end
        else
            print("Error receiving data: " .. err)
        end
        client:close()
    end
end

-- 启动服务器监听
local host = "0.0.0.0"  -- 监听所有 IP 地址
local port = 9527
listen_on_socket(host, port)

