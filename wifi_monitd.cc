#include <iostream>
#include <fstream>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <cstdlib>
#include <sstream>

#include <sys/stat.h>
#include <sys/types.h>
#include <grp.h>

#define SOCKET_PATH "/var/run/monitd.sock"
#define BUFFER_SIZE 4096

std::string getDeviceParams() {
    // Execute `iw dev wlan0 link` and capture its output
    std::string result;
    char buffer[BUFFER_SIZE];
    FILE* pipe = popen("iw dev wlan0 link", "r");
    if (!pipe) {
        return "Error executing iw command.";
    }

    while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        result += buffer;
    }
    pclose(pipe);
    return result;
}

int main() {
    // Create socket
    int server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("Socket creation failed");
        return EXIT_FAILURE;
    }

    // Remove old socket file if it exists
    unlink(SOCKET_PATH);

    struct sockaddr_un address;
    address.sun_family = AF_UNIX;
    strncpy(address.sun_path, SOCKET_PATH, sizeof(address.sun_path) - 1);

    // Bind the socket to the file
    if (bind(server_fd, (struct sockaddr*)&address, sizeof(address)) < 0) {
        perror("Socket bind failed");
        close(server_fd);
        return EXIT_FAILURE;
    }

    // Set file permissions
    chmod(SOCKET_PATH, 0777);
    chown(SOCKET_PATH, -1, getgrnam("www-data")->gr_gid); // 将组改为 www-data

    // Listen for incoming connections
    if (listen(server_fd, 5) < 0) {
        perror("Socket listen failed");
        close(server_fd);
        return EXIT_FAILURE;
    }

    std::cout << "Listening on " << SOCKET_PATH << std::endl;

    while (true) {
        int client_fd = accept(server_fd, nullptr, nullptr);
        if (client_fd < 0) {
            perror("Client accept failed");
            continue;
        }

        // Get device parameters
        std::string params = getDeviceParams();

        // Send data to client
        if (send(client_fd, params.c_str(), params.size(), 0) < 0) {
            perror("Send failed");
        }

        close(client_fd);
    }

    close(server_fd);
    return 0;
}

