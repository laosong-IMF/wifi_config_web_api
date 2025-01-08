#!/usr/bin/lua
local socket = require("socket")  -- 使用 luasocket 来处理 TCP 连接
local cjson = require("cjson")    -- 用于 JSON 编码和解码
local urlencode = require("socket.url").unescape  -- 用于 URL 解码
local io = require("io")

-- 解析接收到的数据
local function handle_request(data, content_type)
    print("Received Data: " .. data)  -- 输出接收到的原始数据

    if content_type == "application/json" then
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
        local cmd = string.format('wpa_passphrase "%s" "%s"', ssid, passwd)
        local handle = io.popen(cmd)

        -- 检查命令是否成功执行
        if handle == nil then
            print("Error executing wpa_passphrase command")  -- 打印错误
            return '{"status":"error","message":"Failed to generate configuration"}', 500
        end

        local result = handle:read("*a")  -- 获取 wpa_passphrase 输出
        handle:close()

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
            print("wpa_supplicant.conf is empty")  -- 打印错误
            return '{"status":"error","message":"Failed to generate configuration"}', 500
        else
            print("wpa_supplicant.conf generated successfully")  -- 打印成功
            return '{"status":"success","message":"Configuration generated successfully"}', 200
        end
    else
        return '{"status":"error","message":"Unsupported Content-Type"}', 415
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

    server:settimeout(10)  -- 设置服务器超时

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

