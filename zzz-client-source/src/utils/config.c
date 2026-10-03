#include "utils/config.h"
#include "utils/ini.h"
#include "utils/log.h"

#include <stdlib.h>
#include <string.h>
#include <net/if.h>

struct Config g_config;

static int hex_char_to_val(char c) {
  if ('0' <= c && c <= '9')
    return c - '0';
  if ('a' <= c && c <= 'f')
    return c - 'a' + 10;
  if ('A' <= c && c <= 'F')
    return c - 'A' + 10;
  return -1;
}

static void unescape_string(char *str) {
  char *src = str, *dst = str;

  while (*src) {
    if (src[0] == '\\' && src[1] == 'x' && src[2] && src[3]) {
      int hi = hex_char_to_val(src[2]);
      int lo = hex_char_to_val(src[3]);
      if (hi >= 0 && lo >= 0) {
        *dst++ = (char)((hi << 4) | lo);
        src += 4;
      } else {
        // invalid \x suffix
        *dst++ = *src++;
      }
    } else {
      *dst++ = *src++;
    }
  }

  *dst = '\0';
}

static int config_handler(void *user, const char *section, const char *name,
                          const char *value) {
  (void)user;
#define MATCH(s, n) strcmp(section, s) == 0 && strcmp(name, n) == 0
  char *copy = strdup(value);
  if (!copy)
    return 0;
  unescape_string(copy);

  if (MATCH("auth", "username")) {
    free((void *)g_config.username);
    g_config.username = copy;
  } else if (MATCH("auth", "password")) {
    free((void *)g_config.password);
    g_config.password = copy;
  } else if (MATCH("auth", "device")) {
    free((void *)g_config.device);
    g_config.device = copy;
  } else {
    free(copy);
    return 1; // unknown section/key — not an error, just skip
  }

  return 1;
}

void config_init(const char *path) {
  if (ini_parse(path, config_handler, &g_config) != 0) {
    log_error("can't parse config from given path", NULL);
    exit(EXIT_FAILURE);
  }

  if (!g_config.device || !*g_config.device ||
      strlen(g_config.device) >= IFNAMSIZ) {
    log_error("missing or invalid auth device", NULL);
    exit(EXIT_FAILURE);
  }
  if (!g_config.username || !*g_config.username) {
    log_error("missing auth username", NULL);
    exit(EXIT_FAILURE);
  }
  if (!g_config.password || !*g_config.password) {
    log_error("missing auth password", NULL);
    exit(EXIT_FAILURE);
  }
}
