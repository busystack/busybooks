// Adapted from BusyMark (BusyStack, Apache-2.0); modified for BusyBooks.
#include "my_application.h"

#include <dlfcn.h>

int main(int argc, char** argv) {
  // The locked sqlite3 system asset requests this exact loader name. Resolve it
  // from the executable (whose RUNPATH contains $ORIGIN/lib), before Flutter's
  // indirect dlopen. RUNPATH is not inherited by callers in libflutter_linux.so.
  // Keep the handle until process exit so subsequent requests reuse this name.
  void* sqlite_runtime = dlopen("libsqlite3.so", RTLD_NOW | RTLD_LOCAL);
  if (sqlite_runtime == nullptr) {
    g_printerr("BusyBooks could not load its SQLite runtime: %s\n", dlerror());
    return 1;
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
