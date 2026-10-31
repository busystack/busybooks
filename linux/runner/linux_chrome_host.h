// Adapted from BusyMark (BusyStack, Apache-2.0); modified for BusyBooks.
#ifndef RUNNER_LINUX_CHROME_HOST_H_
#define RUNNER_LINUX_CHROME_HOST_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

struct BusyBooksLinuxChromeHost;
BusyBooksLinuxChromeHost* busybooks_linux_chrome_host_new(
    FlView* view, GtkWindow* window, void (*set_theme)(gboolean));
void busybooks_linux_chrome_host_free(BusyBooksLinuxChromeHost* host);

#endif
