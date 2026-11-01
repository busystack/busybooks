#ifndef BUSYBOOKS_READER_HOST_H_
#define BUSYBOOKS_READER_HOST_H_
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
struct BusyBooksReaderHost;
BusyBooksReaderHost* busybooks_reader_host_new(GtkWidget* overlay, FlView* view);
void busybooks_reader_host_free(BusyBooksReaderHost* host);
#endif
