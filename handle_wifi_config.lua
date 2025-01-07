#!/usr/bin/lua
local socket = require("socket")  -- 使用 luasocket 来处理 TCP 连接
local cjson = require("cjson")    -- 用于 JSON 编码和解码
local urlencode = require("socket.url").unescape  -- 用于 URL 解码

-- 解析接收到的数据
local function handle_request(data, content_type)
    print("Received Data: " .. data)  -- 输出接收到的原始数据

    if content_type ~= "application/json" then
        -- 如果内容类型不支持，返回 415 错误
        return '{"status":"error","message":"Unsupported Content-Type"}', 415
    end

    -- 解析 JSON 数据
    local success, json_data = pcall(cjson.decode, data)

    if not success then
        -- 如果解析失败，返回 400 错误
        print("JSON Decode Error: " .. json_data)  -- 打印解析错误
        return '{"status":"error","message":"Invalid JSON"}', 400
    end

    local ssid = json_data.ssid
    local passwd = json_data.passwd

    print("Parsed JSON: ssid=" .. ssid .. ", passwd=" .. passwd)  -- 输出解析后的数据

    if not ssid or not passwd then
        -- 如果缺少 ssid 或 passwd，返回 400 错误
        return '{"status":"error","message":"Invalid SSID or password"}', 400
    end

    -- 调用 wpa_passphrase 生成配置文件
    local config_file = "/tmp/wpa_supplicant.conf"
    local cmd = string.format('wpa_passphrase "%s" "%s" > %s', ssid, passwd, config_file)
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()

    if result == "" then
        -- 如果生成配置文件失败，返回 500 错误
        return '{"status":"error","message":"Failed to generate configuration"}', 500
    else
        -- 生成配置成功，返回 200 响应
        return '{"status":"success","message":"Configuration generated successfully"}', 200
    end
end

-- 监听 TCP 套接字并处理请求
local function listen_on_socket(host, port)
    local server, err = socket.bind(host, port)  -- 创建 TCP 套接字并绑定
    if not server then
        print("Error binding to port " .. port .. ": " .. err)  -- 输出错误信息
        return
    end

    print("Server listening on " .. host .. ":" .. port)

    --server:settimeout(10)  -- 设置服务器超时

    while true do
        local client, err = server:accept()  -- 接受客户端连接
        if not client then
            print("Error accepting client connection: " .. err)  -- 输出连接错误信息
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
        local data, err = client:receive(content_length)  -- 根据 Content-Length 读取数据
        if not err then
            -- 处理请求并生成响应
            local response, status_code = handle_request(data, content_type)

            -- 生成 HTTP 响应头
            local content_length = string.len(response)
            local response_header = string.format(
                "HTTP/1.1 %d OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n",
                status_code, content_length
            )

            print("Response Headers: " .. response_header)
            print("Response Body: " .. response)
            -- 发送响应
            client:send(response_header)
            client:send(response)
        else
            print("Error receiving data: " .. err)  -- 输出接收数据错误信息
        end
        client:close()  -- 关闭客户端连接
    end
end

-- 启动服务器监听
local host = "0.0.0.0"  -- 监听所有 IP 地址
local port = 8080       -- 使用端口 8080
listen_on_socket(host, port)

