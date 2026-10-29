// Shared GTK menu host for primary and owned reader Flutter views.
#ifndef BUSYBOOKS_NATIVE_MENU_HOST_H_
#define BUSYBOOKS_NATIVE_MENU_HOST_H_
#include <flutter_linux/flutter_linux.h>
// The caller owns the returned channel and releases it before destroying view.
FlMethodChannel* busybooks_native_menu_host_new(FlView* view);
// Retire callbacks before the owning view is destroyed, then release the channel.
void busybooks_native_menu_host_clear(FlMethodChannel** channel);
// Disabling cancels the owning view's menu and prevents hidden-view requests.
void busybooks_native_menu_host_set_enabled(FlMethodChannel* channel, gboolean enabled);
#endif
