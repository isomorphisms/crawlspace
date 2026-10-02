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
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#define OUTPUT_BYTES 8192

static const unsigned char discovery_magic[4] = {'C', 'S', 'P', '2'};
static const unsigned char response_magic[4] = {'C', 'S', 'R', '2'};

static void fail(const char *message) {
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
}

static int write_all(int fd, const void *buffer, size_t bytes) {
    const unsigned char *current = buffer;
    while (bytes != 0) {
        ssize_t wrote = write(fd, current, bytes);
        if (wrote < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        current += wrote;
        bytes -= (size_t)wrote;
    }
    return 0;
}

static int read_all(int fd, void *buffer, size_t bytes) {
    unsigned char *current = buffer;
    while (bytes != 0) {
        ssize_t got = read(fd, current, bytes);
        if (got == 0) return 0;
        if (got < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        current += got;
        bytes -= (size_t)got;
    }
    return 1;
}

static int write_u32(int fd, uint32_t value) {
    value = htonl(value);
    return write_all(fd, &value, sizeof(value));
}

static int read_u32(int fd, uint32_t *value) {
    uint32_t encoded;
    int result = read_all(fd, &encoded, sizeof(encoded));
    if (result == 1) *value = ntohl(encoded);
    return result;
}

static int reserve_port(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) fail("create port reservation socket");

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        fail("bind port reservation socket");
    }
    socklen_t bytes = sizeof(address);
    if (getsockname(fd, (struct sockaddr *)&address, &bytes) < 0) {
        fail("read reserved port");
    }
    int port = ntohs(address.sin_port);
    close(fd);
    return port;
}

static int connect_to(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons((uint16_t)port);
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static void wait_for_listener(int port) {
    for (int attempt = 0; attempt < 100; attempt++) {
        int fd = connect_to(port);
        if (fd >= 0) {
            close(fd);
            return;
        }
        usleep(10000);
    }
    fail("daemon did not listen");
}

static pid_t start_daemon(const char *binary, const char *token, int port) {
    char port_text[16];
    snprintf(port_text, sizeof(port_text), "%d", port);
    pid_t child = fork();
    if (child < 0) fail("fork daemon");
    if (child == 0) {
        int null = open("/dev/null", O_WRONLY);
        if (null >= 0) {
            dup2(null, STDOUT_FILENO);
            dup2(null, STDERR_FILENO);
            close(null);
        }
        setenv("CRAWLSPACE_TIMEOUT_MS", "250", 1);
        execl(binary, binary, "serve", token, port_text, (char *)NULL);
        _exit(127);
    }
    wait_for_listener(port);
    return child;
}

static void stop_child(pid_t child) {
    if (kill(child, SIGTERM) < 0 && errno != ESRCH) fail("stop child");
    while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {
    }
}

static int run_client(const char *binary,
                      const char *token,
                      int port,
                      const char *timeout,
                      const char *verb,
                      const char *argument,
                      char output[OUTPUT_BYTES]) {
    int pipe_fds[2];
    if (pipe(pipe_fds) < 0) fail("create client output pipe");
    pid_t child = fork();
    if (child < 0) fail("fork client");
    if (child == 0) {
        char port_text[16];
        snprintf(port_text, sizeof(port_text), "%d", port);
        setenv("CRAWLSPACE_PORT", port_text, 1);
        setenv("CRAWLSPACE_TOKEN_FILE", token, 1);
        setenv("CRAWLSPACE_TIMEOUT_MS", timeout, 1);
        close(pipe_fds[0]);
        dup2(pipe_fds[1], STDOUT_FILENO);
        dup2(pipe_fds[1], STDERR_FILENO);
        close(pipe_fds[1]);
        if (argument == NULL) {
            execl(binary, binary, verb, (char *)NULL);
        } else {
            execl(binary, binary, verb, argument, (char *)NULL);
        }
        _exit(127);
    }

    close(pipe_fds[1]);
    size_t used = 0;
    while (used + 1 < OUTPUT_BYTES) {
        ssize_t got = read(pipe_fds[0], output + used,
                           OUTPUT_BYTES - used - 1);
        if (got == 0) break;
        if (got < 0) {
            if (errno == EINTR) continue;
            fail("read client output");
        }
        used += (size_t)got;
    }
    output[used] = '\0';
    close(pipe_fds[0]);

    int status;
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : 255;
}

static pid_t start_client_process(const char *binary,
                                  const char *token,
                                  int port,
                                  const char *verb,
                                  const char *argument) {
    pid_t child = fork();
    if (child < 0) fail("fork asynchronous client");
    if (child == 0) {
        char port_text[16];
        snprintf(port_text, sizeof(port_text), "%d", port);
        setenv("CRAWLSPACE_PORT", port_text, 1);
        setenv("CRAWLSPACE_TOKEN_FILE", token, 1);
        setenv("CRAWLSPACE_TIMEOUT_MS", "500", 1);
        int null = open("/dev/null", O_WRONLY);
        if (null >= 0) {
            dup2(null, STDOUT_FILENO);
            dup2(null, STDERR_FILENO);
            close(null);
        }
        if (argument == NULL) {
            execl(binary, binary, verb, (char *)NULL);
        } else {
            execl(binary, binary, verb, argument, (char *)NULL);
        }
        _exit(127);
    }
    return child;
}

static int wait_client_process(pid_t child) {
    int status;
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : 255;
}

static void wait_for_file(const char *path) {
    for (int attempt = 0; attempt < 200; attempt++) {
        if (access(path, F_OK) == 0) return;
        usleep(10000);
    }
    fail("worker did not reach its started marker");
}


static int run_client_two_streams(const char *binary,
                                  const char *token,
                                  int port,
                                  const char *const args[],
                                  size_t arg_count,
                                  char stdout_output[OUTPUT_BYTES],
                                  char stderr_output[OUTPUT_BYTES]) {
    int stdout_pipe[2];
    int stderr_pipe[2];
    if (pipe(stdout_pipe) < 0 || pipe(stderr_pipe) < 0) {
        fail("create two-stream client pipes");
    }

    pid_t child = fork();
    if (child < 0) fail("fork two-stream client");
    if (child == 0) {
        char port_text[16];
        snprintf(port_text, sizeof(port_text), "%d", port);
        setenv("CRAWLSPACE_PORT", port_text, 1);
        setenv("CRAWLSPACE_TOKEN_FILE", token, 1);
        setenv("CRAWLSPACE_TIMEOUT_MS", "500", 1);
        close(stdout_pipe[0]);
        close(stderr_pipe[0]);
        dup2(stdout_pipe[1], STDOUT_FILENO);
        dup2(stderr_pipe[1], STDERR_FILENO);
        close(stdout_pipe[1]);
        close(stderr_pipe[1]);

        char **argv = calloc(arg_count + 2, sizeof(*argv));
        if (argv == NULL) _exit(126);
        argv[0] = (char *)binary;
        for (size_t i = 0; i < arg_count; i++) {
            argv[i + 1] = (char *)args[i];
        }
        argv[arg_count + 1] = NULL;
        execv(binary, argv);
        _exit(127);
    }

    close(stdout_pipe[1]);
    close(stderr_pipe[1]);

    size_t out_used = 0;
    size_t err_used = 0;
    int out_open = 1;
    int err_open = 1;
    while (out_open || err_open) {
        struct pollfd fds[2];
        int which[2];
        nfds_t count = 0;
        if (out_open) {
            fds[count].fd = stdout_pipe[0];
            fds[count].events = POLLIN | POLLHUP;
            fds[count].revents = 0;
            which[count++] = 1;
        }
        if (err_open) {
            fds[count].fd = stderr_pipe[0];
            fds[count].events = POLLIN | POLLHUP;
            fds[count].revents = 0;
            which[count++] = 2;
        }
        int ready;
        do {
            ready = poll(fds, count, 1000);
        } while (ready < 0 && errno == EINTR);
        if (ready < 0) fail("poll two-stream client");

        for (nfds_t i = 0; i < count; i++) {
            if (fds[i].revents == 0) continue;
            char *buffer = which[i] == 1 ? stdout_output : stderr_output;
            size_t *used = which[i] == 1 ? &out_used : &err_used;
            int fd = fds[i].fd;
            ssize_t got = read(fd, buffer + *used,
                               OUTPUT_BYTES - *used - 1);
            if (got == 0) {
                close(fd);
                if (which[i] == 1) out_open = 0;
                else err_open = 0;
            } else if (got > 0) {
                *used += (size_t)got;
                if (*used + 1 >= OUTPUT_BYTES) {
                    fail("two-stream client output overflow");
                }
            } else if (errno != EINTR) {
                fail("read two-stream client output");
            }
        }
    }

    stdout_output[out_used] = '\0';
    stderr_output[err_used] = '\0';

    int status;
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : 255;
}

static void expect_contains(const char *output, const char *expected) {
    if (strstr(output, expected) == NULL) {
        fprintf(stderr, "missing [%s] in:\n%s\n", expected, output);
        fail("client output mismatch");
    }
}

static size_t count_occurrences(const char *text, const char *needle) {
    size_t count = 0;
    size_t needle_bytes = strlen(needle);
    while ((text = strstr(text, needle)) != NULL) {
        count++;
        text += needle_bytes;
    }
    return count;
}

static void extract_identity(const char *output, char identity[33]) {
    const char *start = strstr(output, "daemon_identity=");
    if (start == NULL) fail("missing daemon identity");
    start += strlen("daemon_identity=");
    memcpy(identity, start, 32);
    identity[32] = '\0';
    for (size_t i = 0; i < 32; i++) {
        if (!((identity[i] >= '0' && identity[i] <= '9') ||
              (identity[i] >= 'a' && identity[i] <= 'f'))) {
            fail("invalid daemon identity");
        }
    }
}

static uint32_t raw_discovery_status(int port,
                                     const char *token,
                                     uint32_t operation,
                                     uint32_t identity_bytes) {
    int fd = connect_to(port);
    if (fd < 0) fail("connect raw discovery request");
    if (write_all(fd, discovery_magic, sizeof(discovery_magic)) < 0 ||
        write_u32(fd, (uint32_t)strlen(token)) < 0 ||
        write_all(fd, token, strlen(token)) < 0 ||
        write_u32(fd, operation) < 0 ||
        write_u32(fd, identity_bytes) < 0 ||
        (identity_bytes != 0 && write_all(fd, "x", 1) < 0)) {
        fail("write raw discovery request");
    }
    unsigned char received_magic[4];
    uint32_t status;
    if (read_all(fd, received_magic, sizeof(received_magic)) != 1 ||
        memcmp(received_magic, response_magic, sizeof(response_magic)) != 0 ||
        read_u32(fd, &status) != 1) {
        fail("read raw discovery response");
    }
    close(fd);
    return status;
}

static pid_t start_stall_server(int port) {
    pid_t child = fork();
    if (child < 0) fail("fork stall server");
    if (child == 0) {
        int listener = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in address;
        memset(&address, 0, sizeof(address));
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        address.sin_port = htons((uint16_t)port);
        int reuse = 1;
        setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
        if (listener < 0 ||
            bind(listener, (struct sockaddr *)&address, sizeof(address)) < 0 ||
            listen(listener, 1) < 0) _exit(2);
        int connection = accept(listener, NULL, NULL);
        if (connection >= 0) {
            sleep(2);
            close(connection);
        }
        close(listener);
        _exit(0);
    }
    wait_for_listener(port);
    return child;
}

int main(int argc, char **argv) {
    if (argc == 1) {
        usleep(350000);
        return 0;
    }
    if (argc != 2) fail("usage: protocol_test CRAWLSPACE_BINARY");

    char directory[] = "/tmp/crawlspace-protocol-XXXXXX";
    if (mkdtemp(directory) == NULL) fail("make temporary directory");
    char token_path[512];
    char wrong_token_path[512];
    snprintf(token_path, sizeof(token_path), "%s/token", directory);
    snprintf(wrong_token_path, sizeof(wrong_token_path), "%s/wrong-token",
             directory);
    FILE *token = fopen(token_path, "w");
    FILE *wrong_token = fopen(wrong_token_path, "w");
    if (token == NULL || wrong_token == NULL) fail("create tokens");
    fputs("host-test-token\n", token);
    fputs("wrong-token\n", wrong_token);
    fclose(token);
    fclose(wrong_token);

    int port = reserve_port();
    pid_t daemon = start_daemon(argv[1], token_path, port);
    char output[OUTPUT_BYTES];
    if (run_client(argv[1], token_path, port, "500", "discover", NULL,
                   output) != 0) fail("initial discovery");
    expect_contains(output, "status=ready\n");
    expect_contains(output, "transport_version=2\n");
    expect_contains(output, "discovery_version=1\n");
    expect_contains(output, "authorization_scope=local-bearer-token\n");
    expect_contains(output, "capability=crawlspace.discovery.v1\n");
    expect_contains(output, "capability=crawlspace.run.absolute-path.v1\n");
    expect_contains(output, "capability=crawlspace.runtime-identity.v1\n");
    expect_contains(output, "capability=crawlspace.run-bounded.v1\n");
    if (count_occurrences(output, "capability=") != 4) {
        fail("discovery returned a capability outside the allowlist");
    }
    char first_identity[33];
    extract_identity(output, first_identity);

    if (run_client(argv[1], token_path, port, "500", "identify", NULL,
                   output) != 0) fail("runtime identity");
    expect_contains(output, "status=ready\n");
    expect_contains(output, "identity_version=1\n");
    expect_contains(output, "daemon_authority=root\n");
    expect_contains(output, "daemon_role=native-command-bridge\n");
    expect_contains(output, "build_id=");
    char daemon_pid_text[64];
    snprintf(daemon_pid_text, sizeof(daemon_pid_text),
             "daemon_pid=%u\n", (unsigned)daemon);
    expect_contains(output, daemon_pid_text);

    if (run_client(argv[1], token_path, port, "500", "discover",
                   first_identity, output) != 0) fail("same-daemon discovery");
    expect_contains(output, "status=ready\n");

    if (run_client(argv[1], token_path, port, "500", "run", "/usr/bin/id",
                   output) != 0) fail("legacy run request");
    expect_contains(output, "uid=");

    char test_binary[4096];
    if (realpath(argv[0], test_binary) == NULL) {
        fail("resolve protocol test path");
    }
    if (run_client(argv[1], token_path, port, "100", "run", test_binary,
                   output) != 0) {
        fail("CSP1 run inherited discovery I/O timeout");
    }


    char bounded_path[512];
    snprintf(bounded_path, sizeof(bounded_path),
             "%s/bounded-fixture.sh", directory);
    FILE *bounded = fopen(bounded_path, "w");
    if (bounded == NULL) fail("create bounded fixture");
    fputs("#!/bin/sh\n"
          "case \"$1\" in\n"
          "  streams) printf 'stdout-ok'; printf 'stderr-ok' >&2; exit 7 ;;\n"
          "  truncate) printf 'abcdefghij'; printf 'ABCDEFGHIJ' >&2 ;;\n"
          "  timeout) sleep 2; printf 'late' ;;\n"
          "  *) exit 9 ;;\n"
          "esac\n", bounded);
    fclose(bounded);
    if (chmod(bounded_path, 0700) < 0) fail("chmod bounded fixture");

    char bounded_stdout[OUTPUT_BYTES];
    char bounded_stderr[OUTPUT_BYTES];
    const char *stream_args[] = {
        "run-bounded", "500", "64", "64", bounded_path, "streams"
    };
    int bounded_status = run_client_two_streams(
        argv[1], token_path, port,
        stream_args, sizeof(stream_args) / sizeof(stream_args[0]),
        bounded_stdout, bounded_stderr);
    if (bounded_status != 7) fail("bounded remote exit status");
    if (strcmp(bounded_stdout, "stdout-ok") != 0) {
        fail("bounded stdout separation");
    }
    if (strcmp(bounded_stderr, "stderr-ok") != 0) {
        fail("bounded stderr separation");
    }

    const char *truncate_args[] = {
        "run-bounded", "500", "4", "5", bounded_path, "truncate"
    };
    bounded_status = run_client_two_streams(
        argv[1], token_path, port,
        truncate_args, sizeof(truncate_args) / sizeof(truncate_args[0]),
        bounded_stdout, bounded_stderr);
    if (bounded_status != 75) fail("bounded truncation exit status");
    if (strcmp(bounded_stdout, "abcd") != 0) fail("bounded stdout limit");
    if (strncmp(bounded_stderr, "ABCDE", 5) != 0) {
        fail("bounded stderr limit");
    }
    expect_contains(bounded_stderr, "bounded stdout truncated at 4 bytes");
    expect_contains(bounded_stderr, "bounded stderr truncated at 5 bytes");

    const char *timeout_args[] = {
        "run-bounded", "100", "64", "64", bounded_path, "timeout"
    };
    bounded_status = run_client_two_streams(
        argv[1], token_path, port,
        timeout_args, sizeof(timeout_args) / sizeof(timeout_args[0]),
        bounded_stdout, bounded_stderr);
    if (bounded_status != 124) fail("bounded timeout exit status");
    if (strstr(bounded_stdout, "late") != NULL) {
        fail("bounded timeout allowed late output");
    }
    expect_contains(bounded_stderr, "bounded command timed out");

    if (run_client(argv[1], token_path, port, "500", "discover", NULL,
                   output) != 0) {
        fail("daemon did not recover after bounded timeout");
    }

    if (run_client(argv[1], wrong_token_path, port, "500", "discover", NULL,
                   output) != 77) fail("denied discovery exit status");
    if (strcmp(output, "status=denied\n") != 0) {
        fail("denied discovery response");
    }

    if (raw_discovery_status(port, "host-test-token", 1, 1) != 3) {
        fail("malformed discovery was not rejected");
    }
    if (raw_discovery_status(port, "host-test-token", 99, 0) != 4) {
        fail("unknown discovery operation was not denied");
    }

    int partial = connect_to(port);
    if (partial < 0 || write_all(partial, "C", 1) < 0) {
        fail("start partial request");
    }
    usleep(350000);
    close(partial);
    if (run_client(argv[1], token_path, port, "500", "discover", NULL,
                   output) != 0) {
        fail("daemon did not recover from partial request timeout");
    }

    char slow_path[512];
    char slow_marker[512];
    snprintf(slow_path, sizeof(slow_path), "%s/slow-worker.sh", directory);
    snprintf(slow_marker, sizeof(slow_marker), "%s/slow.started", directory);
    FILE *slow = fopen(slow_path, "w");
    if (slow == NULL) fail("create slow worker");
    fprintf(slow, "#!/bin/sh\n: > '%s'\nsleep 2\n", slow_marker);
    fclose(slow);
    if (chmod(slow_path, 0700) < 0) fail("chmod slow worker");

    pid_t slow_client =
        start_client_process(argv[1], token_path, port, "run", slow_path);
    wait_for_file(slow_marker);

    if (run_client(argv[1], token_path, port, "500", "discover", NULL,
                   output) != 0) {
        fail("discovery blocked behind an active run");
    }
    expect_contains(output, "status=ready\n");

    stop_child(daemon);
    if (run_client(argv[1], token_path, port, "100", "discover", NULL,
                   output) != 69) {
        fail("listener remained reachable after daemon death");
    }
    expect_contains(output, "status=unavailable\nreason=daemon-absent\n");

    if (wait_client_process(slow_client) != 0) {
        fail("in-flight run did not finish after listener death");
    }

    daemon = start_daemon(argv[1], token_path, port);
    if (run_client(argv[1], token_path, port, "500", "discover",
                   first_identity, output) != 0) fail("restart discovery");
    expect_contains(output, "status=restarted\n");
    char second_identity[33];
    extract_identity(output, second_identity);
    if (strcmp(first_identity, second_identity) == 0) {
        fail("daemon identity did not change across restart");
    }

    stop_child(daemon);
    if (run_client(argv[1], token_path, port, "100", "discover", NULL,
                   output) != 69) fail("daemon absence exit status");
    expect_contains(output, "status=unavailable\nreason=daemon-absent\n");

    port = reserve_port();
    pid_t stall = start_stall_server(port);
    if (run_client(argv[1], token_path, port, "100", "discover", NULL,
                   output) != 124) fail("timeout exit status");
    expect_contains(output, "status=unavailable\nreason=timeout\n");
    stop_child(stall);

    unlink(slow_marker);
    unlink(slow_path);
    unlink(bounded_path);
    unlink(token_path);
    unlink(wrong_token_path);
    rmdir(directory);
    puts("PASS: host protocol discovery, runtime identity, bounded separate "
         "streams/limits/timeout, concurrent control, listener disappearance, "
         "restart, absence, timeout, and CSP1 run");
    return 0;
}
