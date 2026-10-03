#include "utils/config.h"
#include "utils/log.h"
#include <stdio.h>

void log_message(LogLevel level, const char *message, ...) {
  (void)level;
  fprintf(stderr, "%s\n", message);
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  config_init(argv[1]);
  for (const unsigned char *p = (const unsigned char *)g_config.password; *p; p++)
    printf("%02x", *p);
  putchar('\n');
  return 0;
}
