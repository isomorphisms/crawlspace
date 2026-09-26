#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define DEFAULT_PORT 49317
#define MAX_ARGS 128
#define MAX_ARG_BYTES 65536
#define MAX_TOKEN_BYTES 256

static const unsigned char magic[4] = {'C', 'S', 'P', '1'};

static void die(const char *message) {
    perror(message);
    exit(1);
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
    unsigned char received_magic[sizeof(magic)];
    if (read_all(connection, received_magic, sizeof(received_magic)) != 1 ||
        memcmp(received_magic, magic, sizeof(magic)) != 0) {
        return;
    }

    uint32_t token_bytes;
    if (read_u32(connection, &token_bytes) != 1 ||
        token_bytes == 0 ||
        token_bytes > MAX_TOKEN_BYTES) {
        return;
    }

    unsigned char received_token[MAX_TOKEN_BYTES];
    if (read_all(connection, received_token, token_bytes) != 1) {
        return;
    }

    if (token_bytes != server_token_bytes ||
        memcmp(received_token, server_token, server_token_bytes) != 0) {
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

static int serve(const char *token_path, int port) {
    uid_t uid = getuid();

    if (uid != 2000 && uid != 0) {
        fprintf(stderr,
                "crawlspace: refusing to serve as uid=%u; "
                "expected shell(2000) or root(0)\n",
                (unsigned)uid);
        return 2;
    }

    unsigned char token[MAX_TOKEN_BYTES];
    size_t token_bytes = load_token(token_path, token, sizeof(token));

    int listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) {
        die("socket");
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

    fprintf(stderr,
            "crawlspace: uid=%u listening on 127.0.0.1:%d\n",
            (unsigned)uid,
            port);

    for (;;) {
        int connection = accept(listener, NULL, NULL);
        if (connection < 0) {
            if (errno == EINTR) {
                continue;
            }
            die("accept");
        }

        run_request(connection, token, token_bytes);
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

static int run_client(int argument_count, char **arguments) {
    int port = DEFAULT_PORT;
    const char *configured_port = getenv("CRAWLSPACE_PORT");
    if (configured_port != NULL && configured_port[0] != '\0') {
        port = parse_port(configured_port);
    }

    unsigned char token[MAX_TOKEN_BYTES];
    size_t token_bytes =
        load_token(client_token_path(), token, sizeof(token));

    int connection = socket(AF_INET, SOCK_STREAM, 0);
    if (connection < 0) {
        die("socket");
    }

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (connect(connection,
                (struct sockaddr *)&address,
                sizeof(address)) < 0) {
        die("connect");
    }

    if (write_all(connection, magic, sizeof(magic)) < 0 ||
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
            "  crawlspace serve TOKEN_FILE [PORT]\n"
            "  crawlspace run /absolute/command [ARG ...]\n");
}

int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN);

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

    usage();
    return 2;
}
