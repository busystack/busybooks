// Adapted from BusyMark (BusyStack, Apache-2.0); modified for BusyBooks.
#ifndef BUSYBOOKS_GTK_ACCENT_HOST_H_
#define BUSYBOOKS_GTK_ACCENT_HOST_H_
#include <flutter_linux/flutter_linux.h>

struct BusyBooksGtkAccentHost;
BusyBooksGtkAccentHost* busybooks_gtk_accent_host_new(FlView* view,
                                                  GtkWidget* window);
void busybooks_gtk_accent_host_free(BusyBooksGtkAccentHost* host);
#endif  // BUSYBOOKS_GTK_ACCENT_HOST_H_
