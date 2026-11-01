#ifndef BUSYBOOKS_GTK_VIEW_RETIREMENT_H_
#define BUSYBOOKS_GTK_VIEW_RETIREMENT_H_

#include <gtk/gtk.h>

// Bind once, on the GTK thread, immediately after creating an owned FlView.
// Binding owns no view, child or application reference while the view is active.
// The application must outlive the active view. Normal GTK destruction removes
// the SDK renderable before this handler runs; existing owners may then only
// release their references. This is not a general object-resurrection owner.
void BusyBooksBindGtkViewRetirement(GApplication* application, GtkWidget* view);

// Embedded FlViews share the main window but must not own its application quit
// handler. Enforce that ownership after every realization, including re-realize.
void BusyBooksBindEmbeddedGtkViewCloseOwnership(GtkWidget* view);

#ifdef BUSYBOOKS_VIEW_RETIREMENT_DIAGNOSTICS
struct BusyBooksGtkViewRetirementCounters {
  guint active_bindings;
  guint retiring_views;
  guint retained_widgets;
  guint application_holds;
  guint pending_releases;
  guint pending_finalizations;
  guint retired_views;
  guint released_views;
  guint last_normal_references;
  guint contract_violations;
};

// Atomic diagnostic snapshots, including live ownership and cumulative events.
BusyBooksGtkViewRetirementCounters BusyBooksGetGtkViewRetirementCounters();
#endif

#endif  // BUSYBOOKS_GTK_VIEW_RETIREMENT_H_
