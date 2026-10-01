#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef CRAWLSPACE_BUILD_ID
#define CRAWLSPACE_BUILD_ID "unknown"
#endif

#define DEFAULT_PORT 49317
#define MAX_ARGS 128
#define MAX_ARG_BYTES 65536
#define MAX_TOKEN_BYTES 256
#define DAEMON_ID_BYTES 16
#define DEFAULT_TIMEOUT_MS 5000

static const unsigned char run_magic[4] = {'C', 'S', 'P', '1'};
static const unsigned char discovery_magic[4] = {'C', 'S', 'P', '2'};
static const unsigned char discovery_response_magic[4] = {'C', 'S', 'R', '2'};

enum discovery_operation {
    DISCOVER_CAPABILITIES = 1,
    DISCOVER_RUNTIME_IDENTITY = 2
};

enum discovery_status {
    DISCOVERY_READY = 0,
    DISCOVERY_RESTARTED = 1,
    DISCOVERY_DENIED = 2,
    DISCOVERY_MALFORMED = 3,
    DISCOVERY_OPERATION_DENIED = 4
};

static const char *const capabilities[] = {
    "crawlspace.discovery.v1",
    "crawlspace.run.absolute-path.v1",
    "crawlspace.runtime-identity.v1"
};

static void die(const char *message) {
    perror(message);
    exit(1);
}

static int set_close_on_exec(int fd) {
    int flags = fcntl(fd, F_GETFD);
    if (flags < 0 || fcntl(fd, F_SETFD, flags | FD_CLOEXEC) < 0) {
        return -1;
    }
    return 0;
}

static void reap_children(int signal_number) {
    (void)signal_number;
    int saved_errno = errno;
    while (waitpid(-1, NULL, WNOHANG) > 0) {
    }
    errno = saved_errno;
}

static int read_all(int fd, void *buffer, size_t bytes) {
    unsigned char *p = buffer;

    while (bytes != 0) {
        ssize_t n = read(fd, p, bytes);
        if (n == 0) {
            return 0;
        }
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }

        p += n;
        bytes -= (size_t)n;
    }

    return 1;
}

static int write_all(int fd, const void *buffer, size_t bytes) {
    const unsigned char *p = buffer;

    while (bytes != 0) {
        ssize_t n = write(fd, p, bytes);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }

        p += n;
        bytes -= (size_t)n;
    }

    return 0;
}

static int read_u32(int fd, uint32_t *value) {
    uint32_t encoded;
    int result = read_all(fd, &encoded, sizeof(encoded));

    if (result == 1) {
        *value = ntohl(encoded);
    }

    return result;
}

static int write_u32(int fd, uint32_t value) {
    uint32_t encoded = htonl(value);
    return write_all(fd, &encoded, sizeof(encoded));
}

static int parse_timeout_ms(void) {
    const char *configured = getenv("CRAWLSPACE_TIMEOUT_MS");
    if (configured == NULL || configured[0] == '\0') {
        return DEFAULT_TIMEOUT_MS;
    }

    char *end = NULL;
    long timeout = strtol(configured, &end, 10);
    if (configured[0] == '\0' || *end != '\0' ||
        timeout < 1 || timeout > 60000) {
        fprintf(stderr, "crawlspace: invalid timeout: %s\n", configured);
        exit(2);
    }
    return (int)timeout;
}

static int set_socket_timeout(int fd, int timeout_ms) {
    struct timeval timeout;
    timeout.tv_sec = timeout_ms / 1000;
    timeout.tv_usec = (timeout_ms % 1000) * 1000;

    if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO,
                   &timeout, sizeof(timeout)) < 0 ||
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO,
                   &timeout, sizeof(timeout)) < 0) {
        return -1;
    }
    return 0;
}

static int connect_with_timeout(int fd,
                                const struct sockaddr *address,
                                socklen_t address_bytes,
                                int timeout_ms) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
        return -1;
    }

    int result = connect(fd, address, address_bytes);
    if (result < 0 && errno == EINPROGRESS) {
        struct pollfd pending = {.fd = fd, .events = POLLOUT};
        do {
            result = poll(&pending, 1, timeout_ms);
        } while (result < 0 && errno == EINTR);

        if (result == 0) {
            errno = ETIMEDOUT;
            result = -1;
        } else if (result > 0) {
            int error = 0;
            socklen_t error_bytes = sizeof(error);
            if (getsockopt(fd, SOL_SOCKET, SO_ERROR,
                           &error, &error_bytes) < 0) {
                result = -1;
            } else if (error != 0) {
                errno = error;
                result = -1;
            } else {
                result = 0;
            }
        }
    }

    int saved_errno = errno;
    if (fcntl(fd, F_SETFL, flags) < 0 && result == 0) {
        return -1;
    }
    errno = saved_errno;
    return result;
}

static int token_matches(const unsigned char *received,
                         size_t received_bytes,
                         const unsigned char *expected,
                         size_t expected_bytes) {
    size_t compared_bytes = received_bytes > expected_bytes
        ? received_bytes : expected_bytes;
    unsigned int difference = (unsigned int)(received_bytes ^ expected_bytes);

    for (size_t i = 0; i < compared_bytes; i++) {
        unsigned char left = i < received_bytes ? received[i] : 0;
        unsigned char right = i < expected_bytes ? expected[i] : 0;
        difference |= (unsigned int)(left ^ right);
    }
    return difference == 0;
}

static int read_token(int connection,
                      unsigned char *received_token,
                      uint32_t *token_bytes) {
    if (read_u32(connection, token_bytes) != 1 ||
        *token_bytes == 0 || *token_bytes > MAX_TOKEN_BYTES) {
        return 0;
    }
    return read_all(connection, received_token, *token_bytes) == 1;
}

static int write_discovery_status(int connection,
                                  enum discovery_status status) {
    return write_all(connection, discovery_response_magic,
                     sizeof(discovery_response_magic)) < 0 ||
           write_u32(connection, (uint32_t)status) < 0
        ? -1 : 0;
}

static int write_counted_bytes(int connection,
                               const void *bytes,
                               size_t byte_count) {
    if (byte_count > UINT32_MAX ||
        write_u32(connection, (uint32_t)byte_count) < 0 ||
        write_all(connection, bytes, byte_count) < 0) {
        return -1;
    }
    return 0;
}

static size_t load_token(const char *path, unsigned char *token, size_t capacity) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        die(path);
    }

    size_t bytes = fread(token, 1, capacity, file);
    if (ferror(file)) {
        fclose(file);
        die("read token");
    }
    fclose(file);

    while (bytes != 0 &&
           (token[bytes - 1] == '\n' || token[bytes - 1] == '\r')) {
        bytes--;
    }

    if (bytes == 0 || bytes == capacity) {
        fprintf(stderr, "crawlspace: invalid token file\n");
        exit(2);
    }

    return bytes;
}

static int parse_port(const char *text) {
    char *end = NULL;
    long port = strtol(text, &end, 10);

    if (text[0] == '\0' || *end != '\0' || port < 1 || port > 65535) {
        fprintf(stderr, "crawlspace: invalid port: %s\n", text);
        exit(2);
    }

    return (int)port;
}

static void free_arguments(char **arguments, uint32_t count) {
    if (arguments == NULL) {
        return;
    }

    for (uint32_t i = 0; i < count; i++) {
        free(arguments[i]);
    }
    free(arguments);
}

static void run_request(int connection,
                        const unsigned char *server_token,
                        size_t server_token_bytes) {
    uint32_t token_bytes;
    unsigned char received_token[MAX_TOKEN_BYTES];
    if (!read_token(connection, received_token, &token_bytes)) {
        return;
    }

    if (!token_matches(received_token, token_bytes,
                       server_token, server_token_bytes)) {
        return;
    }

    uint32_t argument_count;
    if (read_u32(connection, &argument_count) != 1 ||
        argument_count == 0 ||
        argument_count > MAX_ARGS) {
        return;
    }

    char **arguments = calloc((size_t)argument_count + 1, sizeof(*arguments));
    if (arguments == NULL) {
        return;
    }

    for (uint32_t i = 0; i < argument_count; i++) {
        uint32_t bytes;
        if (read_u32(connection, &bytes) != 1 ||
            bytes == 0 ||
            bytes > MAX_ARG_BYTES) {
            free_arguments(arguments, argument_count);
            return;
        }

        arguments[i] = malloc((size_t)bytes + 1);
        if (arguments[i] == NULL ||
            read_all(connection, arguments[i], bytes) != 1) {
            free_arguments(arguments, argument_count);
            return;
        }

        arguments[i][bytes] = '\0';
    }

    if (arguments[0][0] != '/') {
        static const char message[] =
            "crawlspace: command must be an absolute path\n";
        write_u32(connection, sizeof(message) - 1);
        write_all(connection, message, sizeof(message) - 1);
        write_u32(connection, 0);
        write_u32(connection, 126);
        free_arguments(arguments, argument_count);
        return;
    }

    int output[2];
    if (pipe(output) < 0) {
        free_arguments(arguments, argument_count);
        return;
    }

    pid_t child = fork();
    if (child < 0) {
        close(output[0]);
        close(output[1]);
        free_arguments(arguments, argument_count);
        return;
    }

    if (child == 0) {
        close(output[0]);
        close(connection);

        int null_input = open("/dev/null", O_RDONLY);
        if (null_input >= 0) {
            dup2(null_input, STDIN_FILENO);
            close(null_input);
        }

        dup2(output[1], STDOUT_FILENO);
        dup2(output[1], STDERR_FILENO);
        close(output[1]);

        execv(arguments[0], arguments);
        dprintf(STDERR_FILENO,
                "crawlspace: exec %s: %s\n",
                arguments[0],
                strerror(errno));
        _exit(127);
    }

    close(output[1]);

    unsigned char buffer[4096];
    for (;;) {
        ssize_t bytes = read(output[0], buffer, sizeof(buffer));
        if (bytes == 0) {
            break;
        }
        if (bytes < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }

        if (write_u32(connection, (uint32_t)bytes) < 0 ||
            write_all(connection, buffer, (size_t)bytes) < 0) {
            break;
        }
    }
    close(output[0]);

    int status = 0;
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
    }

    uint32_t exit_status = 125;
    if (WIFEXITED(status)) {
        exit_status = (uint32_t)WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        exit_status = (uint32_t)(128 + WTERMSIG(status));
    }

    write_u32(connection, 0);
    write_u32(connection, exit_status);

    free_arguments(arguments, argument_count);
}

static void discovery_request(int connection,
                              const unsigned char *server_token,
                              size_t server_token_bytes,
                              const unsigned char daemon_id[DAEMON_ID_BYTES],
                              uid_t daemon_uid,
                              pid_t daemon_pid) {
    uint32_t token_bytes;
    unsigned char received_token[MAX_TOKEN_BYTES];
    if (!read_token(connection, received_token, &token_bytes)) {
        write_discovery_status(connection, DISCOVERY_MALFORMED);
        return;
    }

    if (!token_matches(received_token, token_bytes,
                       server_token, server_token_bytes)) {
        write_discovery_status(connection, DISCOVERY_DENIED);
        return;
    }

    uint32_t operation;
    if (read_u32(connection, &operation) != 1) {
        write_discovery_status(connection, DISCOVERY_MALFORMED);
        return;
    }
    if (operation != DISCOVER_CAPABILITIES &&
        operation != DISCOVER_RUNTIME_IDENTITY) {
        write_discovery_status(connection, DISCOVERY_OPERATION_DENIED);
        return;
    }

    uint32_t expected_id_bytes;
    if (read_u32(connection, &expected_id_bytes) != 1 ||
        (expected_id_bytes != 0 && expected_id_bytes != DAEMON_ID_BYTES)) {
        write_discovery_status(connection, DISCOVERY_MALFORMED);
        return;
    }

    unsigned char expected_id[DAEMON_ID_BYTES];
    if (expected_id_bytes != 0 &&
        read_all(connection, expected_id, sizeof(expected_id)) != 1) {
        write_discovery_status(connection, DISCOVERY_MALFORMED);
        return;
    }

    enum discovery_status status = DISCOVERY_READY;
    if (expected_id_bytes != 0 &&
        memcmp(expected_id, daemon_id, DAEMON_ID_BYTES) != 0) {
        status = DISCOVERY_RESTARTED;
    }

    if (write_discovery_status(connection, status) < 0) {
        return;
    }

    if (operation == DISCOVER_CAPABILITIES) {
        if (write_u32(connection, 1) < 0 ||
            write_u32(connection, (uint32_t)daemon_uid) < 0 ||
            write_counted_bytes(connection, daemon_id, DAEMON_ID_BYTES) < 0 ||
            write_u32(connection,
                      (uint32_t)(sizeof(capabilities) /
                                 sizeof(capabilities[0]))) < 0) {
            return;
        }

        for (size_t i = 0;
             i < sizeof(capabilities) / sizeof(capabilities[0]);
             i++) {
            if (write_counted_bytes(connection,
                                    capabilities[i],
                                    strlen(capabilities[i])) < 0) {
                return;
            }
        }
        return;
    }

    const char *authority = daemon_uid == 0 ? "root" : "shell";
    static const char role[] = "native-command-bridge";
    if (write_u32(connection, 1) < 0 ||
        write_u32(connection, (uint32_t)daemon_uid) < 0 ||
        write_u32(connection, (uint32_t)daemon_pid) < 0 ||
        write_counted_bytes(connection, daemon_id, DAEMON_ID_BYTES) < 0 ||
        write_counted_bytes(connection, role, sizeof(role) - 1) < 0 ||
        write_counted_bytes(connection, authority, strlen(authority)) < 0 ||
        write_counted_bytes(connection,
                            CRAWLSPACE_BUILD_ID,
                            strlen(CRAWLSPACE_BUILD_ID)) < 0) {
        return;
    }
}

static void handle_connection(int connection,
                              const unsigned char *server_token,
                              size_t server_token_bytes,
                              const unsigned char daemon_id[DAEMON_ID_BYTES],
                              uid_t daemon_uid,
                              pid_t daemon_pid) {
    unsigned char received_magic[sizeof(run_magic)];
    if (read_all(connection, received_magic, sizeof(received_magic)) != 1) {
        return;
    }

    if (memcmp(received_magic, run_magic, sizeof(run_magic)) == 0) {
        run_request(connection, server_token, server_token_bytes);
    } else if (memcmp(received_magic, discovery_magic,
                      sizeof(discovery_magic)) == 0) {
        discovery_request(connection, server_token, server_token_bytes,
                          daemon_id, daemon_uid, daemon_pid);
    }
}

static void make_daemon_id(unsigned char daemon_id[DAEMON_ID_BYTES]) {
    int random = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
    if (random < 0) {
        die("open /dev/urandom");
    }
    if (read_all(random, daemon_id, DAEMON_ID_BYTES) != 1) {
        close(random);
        die("read /dev/urandom");
    }
    close(random);
}

static int serve(const char *token_path, int port) {
    uid_t uid = getuid();
    pid_t daemon_pid = getpid();

    if (uid != 2000 && uid != 0) {
        fprintf(stderr,
                "crawlspace: refusing to serve as uid=%u; "
                "expected shell(2000) or root(0)\n",
                (unsigned)uid);
        return 2;
    }

    unsigned char token[MAX_TOKEN_BYTES];
    size_t token_bytes = load_token(token_path, token, sizeof(token));
    unsigned char daemon_id[DAEMON_ID_BYTES];
    make_daemon_id(daemon_id);
    int timeout_ms = parse_timeout_ms();

    int listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) {
        die("socket");
    }
    if (set_close_on_exec(listener) < 0) {
        die("listener close-on-exec");
    }

    int reuse = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) < 0) {
        die("bind");
    }
    if (listen(listener, 8) < 0) {
        die("listen");
    }

    struct sigaction child_action;
    memset(&child_action, 0, sizeof(child_action));
    child_action.sa_handler = reap_children;
    sigemptyset(&child_action.sa_mask);
    child_action.sa_flags = SA_RESTART | SA_NOCLDSTOP;
    if (sigaction(SIGCHLD, &child_action, NULL) < 0) {
        die("sigaction SIGCHLD");
    }

    fprintf(stderr,
            "crawlspace: uid=%u pid=%u listening on 127.0.0.1:%d\n",
            (unsigned)uid,
            (unsigned)daemon_pid,
            port);

    for (;;) {
        int connection = accept(listener, NULL, NULL);
        if (connection < 0) {
            if (errno == EINTR) {
                continue;
            }
            die("accept");
        }

        if (set_close_on_exec(connection) < 0 ||
            set_socket_timeout(connection, timeout_ms) < 0) {
            close(connection);
            continue;
        }

        pid_t handler = fork();
        if (handler < 0) {
            close(connection);
            continue;
        }
        if (handler == 0) {
            signal(SIGCHLD, SIG_DFL);
            close(listener);
            handle_connection(connection, token, token_bytes,
                              daemon_id, uid, daemon_pid);
            close(connection);
            _exit(0);
        }

        close(connection);
    }
}

static const char *client_token_path(void) {
    const char *configured = getenv("CRAWLSPACE_TOKEN_FILE");
    if (configured != NULL && configured[0] != '\0') {
        return configured;
    }

    const char *home = getenv("HOME");
    if (home == NULL || home[0] == '\0') {
        fprintf(stderr,
                "crawlspace: HOME is unset; set CRAWLSPACE_TOKEN_FILE\n");
        exit(2);
    }

    static char path[1024];
    int written = snprintf(path,
                           sizeof(path),
                           "%s/.config/crawlspace/token",
                           home);
    if (written < 0 || (size_t)written >= sizeof(path)) {
        fprintf(stderr, "crawlspace: token path is too long\n");
        exit(2);
    }

    return path;
}

static int configured_port(void) {
    const char *configured = getenv("CRAWLSPACE_PORT");
    return configured != NULL && configured[0] != '\0'
        ? parse_port(configured) : DEFAULT_PORT;
}

static int open_client_connection(int port,
                                  int timeout_ms,
                                  int apply_io_timeout,
                                  int report_availability) {
    int connection = socket(AF_INET, SOCK_STREAM, 0);
    if (connection < 0) {
        die("socket");
    }
    if (set_close_on_exec(connection) < 0) {
        close(connection);
        die("client close-on-exec");
    }

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (connect_with_timeout(connection,
                             (struct sockaddr *)&address,
                             sizeof(address), timeout_ms) < 0) {
        int error = errno;
        close(connection);
        if (!report_availability) {
            errno = error;
            perror("crawlspace: connect");
            return -1;
        }
        if (error == ETIMEDOUT) {
            printf("status=unavailable\nreason=timeout\n");
            return -124;
        }
        if (error == ECONNREFUSED || error == ENETUNREACH ||
            error == EHOSTUNREACH || error == ENOENT) {
            printf("status=unavailable\nreason=daemon-absent\n");
            return -69;
        }
        errno = error;
        perror("crawlspace: connect");
        return -69;
    }

    if (apply_io_timeout && set_socket_timeout(connection, timeout_ms) < 0) {
        close(connection);
        die("set socket timeout");
    }
    return connection;
}

static int timed_out(void) {
    return errno == EAGAIN || errno == EWOULDBLOCK || errno == ETIMEDOUT;
}

static int decode_daemon_id(const char *text,
                            unsigned char identity[DAEMON_ID_BYTES]) {
    if (strlen(text) != DAEMON_ID_BYTES * 2) {
        return 0;
    }

    for (size_t i = 0; i < DAEMON_ID_BYTES; i++) {
        unsigned int value = 0;
        for (size_t half = 0; half < 2; half++) {
            unsigned char character = (unsigned char)text[i * 2 + half];
            unsigned int digit;
            if (character >= '0' && character <= '9') {
                digit = character - '0';
            } else if (character >= 'a' && character <= 'f') {
                digit = character - 'a' + 10;
            } else if (character >= 'A' && character <= 'F') {
                digit = character - 'A' + 10;
            } else {
                return 0;
            }
            value = value * 16 + digit;
        }
        identity[i] = (unsigned char)value;
    }
    return 1;
}

static void print_daemon_id(const unsigned char identity[DAEMON_ID_BYTES]) {
    for (size_t i = 0; i < DAEMON_ID_BYTES; i++) {
        printf("%02x", identity[i]);
    }
}

static int read_counted_text(int fd, char *buffer, size_t capacity) {
    uint32_t bytes;
    if (capacity == 0 ||
        read_u32(fd, &bytes) != 1 ||
        bytes == 0 ||
        bytes >= capacity ||
        read_all(fd, buffer, bytes) != 1) {
        return 0;
    }
    buffer[bytes] = '\0';
    return 1;
}

static int discovery_client(const char *expected_identity_text) {
    unsigned char expected_identity[DAEMON_ID_BYTES];
    uint32_t expected_identity_bytes = 0;
    if (expected_identity_text != NULL) {
        if (!decode_daemon_id(expected_identity_text, expected_identity)) {
            fprintf(stderr,
                    "crawlspace: expected daemon identity must be "
                    "%d hexadecimal characters\n",
                    DAEMON_ID_BYTES * 2);
            return 2;
        }
        expected_identity_bytes = DAEMON_ID_BYTES;
    }

    unsigned char token[MAX_TOKEN_BYTES];
    size_t token_bytes = load_token(client_token_path(), token, sizeof(token));
    int connection = open_client_connection(configured_port(),
                                            parse_timeout_ms(), 1, 1);
    if (connection < 0) {
        return -connection;
    }

    if (write_all(connection, discovery_magic, sizeof(discovery_magic)) < 0 ||
        write_u32(connection, (uint32_t)token_bytes) < 0 ||
        write_all(connection, token, token_bytes) < 0 ||
        write_u32(connection, DISCOVER_CAPABILITIES) < 0 ||
        write_u32(connection, expected_identity_bytes) < 0 ||
        (expected_identity_bytes != 0 &&
         write_all(connection, expected_identity,
                   sizeof(expected_identity)) < 0)) {
        int timeout = timed_out();
        close(connection);
        if (timeout) {
            printf("status=unavailable\nreason=timeout\n");
            return 124;
        }
        fprintf(stderr, "crawlspace: failed to write discovery request\n");
        return 125;
    }

    unsigned char response_magic[sizeof(discovery_response_magic)];
    uint32_t status;
    if (read_all(connection, response_magic, sizeof(response_magic)) != 1 ||
        memcmp(response_magic, discovery_response_magic,
               sizeof(response_magic)) != 0 ||
        read_u32(connection, &status) != 1) {
        int timeout = timed_out();
        close(connection);
        if (timeout) {
            printf("status=unavailable\nreason=timeout\n");
            return 124;
        }
        fprintf(stderr, "crawlspace: malformed discovery response\n");
        return 65;
    }

    if (status == DISCOVERY_DENIED ||
        status == DISCOVERY_OPERATION_DENIED) {
        close(connection);
        printf("status=denied\n");
        return 77;
    }
    if (status == DISCOVERY_MALFORMED ||
        (status != DISCOVERY_READY && status != DISCOVERY_RESTARTED)) {
        close(connection);
        fprintf(stderr, "crawlspace: daemon rejected malformed discovery\n");
        return 65;
    }

    uint32_t discovery_version;
    uint32_t daemon_uid;
    uint32_t daemon_id_bytes;
    unsigned char daemon_id[DAEMON_ID_BYTES];
    uint32_t capability_count;
    if (read_u32(connection, &discovery_version) != 1 ||
        discovery_version != 1 ||
        read_u32(connection, &daemon_uid) != 1 ||
        read_u32(connection, &daemon_id_bytes) != 1 ||
        daemon_id_bytes != DAEMON_ID_BYTES ||
        read_all(connection, daemon_id, sizeof(daemon_id)) != 1 ||
        read_u32(connection, &capability_count) != 1 ||
        capability_count > 32) {
        close(connection);
        fprintf(stderr, "crawlspace: malformed discovery response\n");
        return 65;
    }

    printf("status=%s\ntransport_version=2\ndiscovery_version=%u\n",
           status == DISCOVERY_RESTARTED ? "restarted" : "ready",
           discovery_version);
    printf("daemon_identity=");
    print_daemon_id(daemon_id);
    printf("\ndaemon_uid=%u\nauthorization_scope=local-bearer-token\n",
           daemon_uid);

    for (uint32_t i = 0; i < capability_count; i++) {
        char capability[129];
        if (!read_counted_text(connection, capability, sizeof(capability))) {
            close(connection);
            fprintf(stderr, "crawlspace: malformed discovery response\n");
            return 65;
        }
        printf("capability=%s\n", capability);
    }

    close(connection);
    return 0;
}

static int runtime_identity_client(const char *expected_identity_text) {
    unsigned char expected_identity[DAEMON_ID_BYTES];
    uint32_t expected_identity_bytes = 0;
    if (expected_identity_text != NULL) {
        if (!decode_daemon_id(expected_identity_text, expected_identity)) {
            fprintf(stderr,
                    "crawlspace: expected daemon identity must be "
                    "%d hexadecimal characters\n",
                    DAEMON_ID_BYTES * 2);
            return 2;
        }
        expected_identity_bytes = DAEMON_ID_BYTES;
    }

    unsigned char token[MAX_TOKEN_BYTES];
    size_t token_bytes = load_token(client_token_path(), token, sizeof(token));
    int connection = open_client_connection(configured_port(),
                                            parse_timeout_ms(), 1, 1);
    if (connection < 0) {
        return -connection;
    }

    if (write_all(connection, discovery_magic, sizeof(discovery_magic)) < 0 ||
        write_u32(connection, (uint32_t)token_bytes) < 0 ||
        write_all(connection, token, token_bytes) < 0 ||
        write_u32(connection, DISCOVER_RUNTIME_IDENTITY) < 0 ||
        write_u32(connection, expected_identity_bytes) < 0 ||
        (expected_identity_bytes != 0 &&
         write_all(connection, expected_identity,
                   sizeof(expected_identity)) < 0)) {
        int timeout = timed_out();
        close(connection);
        if (timeout) {
            printf("status=unavailable\nreason=timeout\n");
            return 124;
        }
        fprintf(stderr, "crawlspace: failed to write identity request\n");
        return 125;
    }

    unsigned char response_magic[sizeof(discovery_response_magic)];
    uint32_t status;
    if (read_all(connection, response_magic, sizeof(response_magic)) != 1 ||
        memcmp(response_magic, discovery_response_magic,
               sizeof(response_magic)) != 0 ||
        read_u32(connection, &status) != 1) {
        int timeout = timed_out();
        close(connection);
        if (timeout) {
            printf("status=unavailable\nreason=timeout\n");
            return 124;
        }
        fprintf(stderr, "crawlspace: malformed identity response\n");
        return 65;
    }

    if (status == DISCOVERY_DENIED ||
        status == DISCOVERY_OPERATION_DENIED) {
        close(connection);
        printf("status=denied\n");
        return 77;
    }
    if (status == DISCOVERY_MALFORMED ||
        (status != DISCOVERY_READY && status != DISCOVERY_RESTARTED)) {
        close(connection);
        fprintf(stderr, "crawlspace: daemon rejected malformed identity request\n");
        return 65;
    }

    uint32_t identity_version;
    uint32_t daemon_uid;
    uint32_t daemon_pid;
    uint32_t daemon_id_bytes;
    unsigned char daemon_id[DAEMON_ID_BYTES];
    char role[65];
    char authority[17];
    char build_id[129];

    if (read_u32(connection, &identity_version) != 1 ||
        identity_version != 1 ||
        read_u32(connection, &daemon_uid) != 1 ||
        read_u32(connection, &daemon_pid) != 1 ||
        read_u32(connection, &daemon_id_bytes) != 1 ||
        daemon_id_bytes != DAEMON_ID_BYTES ||
        read_all(connection, daemon_id, sizeof(daemon_id)) != 1 ||
        !read_counted_text(connection, role, sizeof(role)) ||
        !read_counted_text(connection, authority, sizeof(authority)) ||
        !read_counted_text(connection, build_id, sizeof(build_id))) {
        close(connection);
        fprintf(stderr, "crawlspace: malformed identity response\n");
        return 65;
    }

    printf("status=%s\ntransport_version=2\nidentity_version=%u\n",
           status == DISCOVERY_RESTARTED ? "restarted" : "ready",
           identity_version);
    printf("daemon_start_identity=");
    print_daemon_id(daemon_id);
    printf("\ndaemon_pid=%u\ndaemon_uid=%u\n", daemon_pid, daemon_uid);
    printf("daemon_authority=%s\ndaemon_role=%s\nbuild_id=%s\n",
           authority, role, build_id);
    printf("authorization_scope=local-bearer-token\n");

    close(connection);
    return 0;
}

static int run_client(int argument_count, char **arguments) {
    unsigned char token[MAX_TOKEN_BYTES];
    size_t token_bytes =
        load_token(client_token_path(), token, sizeof(token));
    int connection = open_client_connection(configured_port(),
                                            parse_timeout_ms(), 0, 0);
    if (connection < 0) {
        return -connection;
    }

    if (write_all(connection, run_magic, sizeof(run_magic)) < 0 ||
        write_u32(connection, (uint32_t)token_bytes) < 0 ||
        write_all(connection, token, token_bytes) < 0 ||
        write_u32(connection, (uint32_t)argument_count) < 0) {
        die("write request");
    }

    for (int i = 0; i < argument_count; i++) {
        size_t bytes = strlen(arguments[i]);
        if (bytes == 0 || bytes > MAX_ARG_BYTES) {
            fprintf(stderr, "crawlspace: invalid argument length\n");
            return 2;
        }

        if (write_u32(connection, (uint32_t)bytes) < 0 ||
            write_all(connection, arguments[i], bytes) < 0) {
            die("write request");
        }
    }

    for (;;) {
        uint32_t bytes;
        if (read_u32(connection, &bytes) != 1) {
            fprintf(stderr,
                    "crawlspace: connection closed without an exit status\n");
            return 125;
        }

        if (bytes == 0) {
            break;
        }

        unsigned char buffer[4096];
        while (bytes != 0) {
            size_t chunk = bytes < sizeof(buffer) ? bytes : sizeof(buffer);
            if (read_all(connection, buffer, chunk) != 1) {
                fprintf(stderr, "crawlspace: truncated response\n");
                return 125;
            }
            if (write_all(STDOUT_FILENO, buffer, chunk) < 0) {
                die("write stdout");
            }
            bytes -= (uint32_t)chunk;
        }
    }

    uint32_t exit_status;
    if (read_u32(connection, &exit_status) != 1) {
        return 125;
    }

    close(connection);

    if (exit_status > 255) {
        return 125;
    }
    return (int)exit_status;
}

static void usage(void) {
    fprintf(stderr,
            "usage:\n"
            "  crawlspace --version\n"
            "  crawlspace serve TOKEN_FILE [PORT]\n"
            "  crawlspace discover [EXPECTED_DAEMON_ID]\n"
            "  crawlspace identify [EXPECTED_DAEMON_ID]\n"
            "  crawlspace run /absolute/command [ARG ...]\n");
}

int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN);

    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        printf("crawlspace transport=2 discovery=1\n");
        return 0;
    }

    if (argc >= 3 && strcmp(argv[1], "serve") == 0) {
        int port = DEFAULT_PORT;
        if (argc >= 4) {
            port = parse_port(argv[3]);
        }
        return serve(argv[2], port);
    }

    if (argc >= 3 && strcmp(argv[1], "run") == 0) {
        return run_client(argc - 2, argv + 2);
    }

    if ((argc == 2 || argc == 3) && strcmp(argv[1], "discover") == 0) {
        return discovery_client(argc == 3 ? argv[2] : NULL);
    }

    if ((argc == 2 || argc == 3) && strcmp(argv[1], "identify") == 0) {
        return runtime_identity_client(argc == 3 ? argv[2] : NULL);
    }

    usage();
    return 2;
}
